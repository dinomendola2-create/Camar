
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wakelock/wakelock.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CamarApp());
}

class RelayConfig {
  String name;
  RelayConfig({required this.name});
  Map<String,dynamic> toJson() => {'name': name};
  static RelayConfig fromJson(Map<String,dynamic> j) => RelayConfig(name: j['name'] ?? '');
}

class Group {
  String name;
  List<int> relays;
  Group({required this.name, required this.relays});
  Map<String,dynamic> toJson() => {'name': name, 'relays': relays};
  static Group fromJson(Map<String,dynamic> j) => Group(name: j['name'], relays: List<int>.from(j['relays']));
}

class Board {
  String name;
  String ip;
  List<RelayConfig> relayConfigs;
  List<Group> groups;
  List<bool> relayStates;
  List<int> relayTimers;
  List<Map<String,dynamic>> logs;
  Board({required this.name, required this.ip, List<RelayConfig>? relayConfigs, List<Group>? groups})
      : relayConfigs = relayConfigs ?? List.generate(8, (i)=> RelayConfig(name: 'Relè ${i}')),
        groups = groups ?? [],
        relayStates = List<bool>.filled(8,false),
        relayTimers = List<int>.filled(8,0),
        logs = [];
  Map<String,dynamic> toJson() => {
    'name': name,
    'ip': ip,
    'relayConfigs': relayConfigs.map((r)=>r.toJson()).toList(),
    'groups': groups.map((g)=>g.toJson()).toList(),
    'relayStates': relayStates,
    'relayTimers': relayTimers,
    'logs': logs,
  };
  static Board fromJson(Map<String,dynamic> j){
    final b = Board(name: j['name'] ?? 'Board', ip: j['ip'] ?? 'http://192.168.1.50',
      relayConfigs: j['relayConfigs'] != null ? (j['relayConfigs'] as List).map((e)=> RelayConfig.fromJson(Map<String,dynamic>.from(e))).toList() : null,
      groups: j['groups'] != null ? (j['groups'] as List).map((e)=> Group.fromJson(Map<String,dynamic>.from(e))).toList() : null,
    );
    try { if (j['relayStates']!=null) b.relayStates = List<bool>.from((j['relayStates'] as List).map((e)=> e==true)); } catch(_) {}
    try { if (j['relayTimers']!=null) b.relayTimers = List<int>.from(j['relayTimers']); } catch(_) {}
    try { if (j['logs']!=null) b.logs = (j['logs'] as List).map((e)=> Map<String,dynamic>.from(e)).toList(); } catch(_) {}
    return b;
  }
}

class CamarApp extends StatelessWidget {
  const CamarApp({super.key});
  @override Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Camar',
      theme: ThemeData(useMaterial3: true),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  List<Board> boards = [];
  late TabController tabController;
  late stt.SpeechToText speech;
  final FlutterTts tts = FlutterTts();
  bool isListening=false;
  List<List<Timer?>> boardTimers = [];

  @override
  void initState(){
    super.initState();
    speech = stt.SpeechToText();
    _load().then((_) {
      tabController = TabController(length: boards.length, vsync: this);
      boardTimers = List.generate(boards.length, (_) => List<Timer?>.filled(8,null));
      setState((){});
    });
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString('camar_boards');
    if (s!=null){
      try {
        final arr = json.decode(s) as List;
        boards = arr.map((e)=> Board.fromJson(Map<String,dynamic>.from(e))).toList();
      } catch(_) { boards = []; }
    }
    if (boards.isEmpty) boards = [ Board(name:'Default', ip:'http://192.168.1.50') ];
    await _save();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('camar_boards', json.encode(boards.map((b)=> b.toJson()).toList()));
  }

  void _addLog(Board b, String type, String msg){
    final e={'type':type,'message':msg,'time': DateTime.now().toIso8601String()};
    setState(()=> b.logs.insert(0,e));
    _save();
  }

  Future<bool> _sendHttp(Board b, int relay, bool on) async {
    final url = '${b.ip}/leds.cgi?led=$relay&${on? 'on':'off'}';
    _addLog(b,'HTTP','Send: $url');
    try {
      final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds:4));
      _addLog(b,'HTTP','Response: ${r.statusCode}');
      return r.statusCode>=200 && r.statusCode<300;
    } catch(e){
      _addLog(b,'ERROR','HTTP error: $e');
      return false;
    }
  }

  Future<void> _setRelay(Board b, int boardIndex, int relay, bool on, {int? timerSec}) async {
    boardTimers[boardIndex][relay]?.cancel();
    boardTimers[boardIndex][relay]=null;
    final ok = await _sendHttp(b, relay, on);
    setState(()=> b.relayStates[relay]=on);
    _addLog(b,'INFO','${on? 'On':'Off'} ${b.relayConfigs[relay].name} (R$relay) HTTP:${ok? 'OK':'ERR'}');
    await tts.speak('${on? 'Acceso':'Spento'} ${b.relayConfigs[relay].name}');
    if (on && timerSec!=null && timerSec>0){
      b.relayTimers[relay]=timerSec;
      _addLog(b,'TIMER','Timer start R$relay $timerSec s');
      boardTimers[boardIndex][relay]= Timer.periodic(const Duration(seconds:1), (t) async {
        setState(()=> b.relayTimers[relay]--);
        if (b.relayTimers[relay]<=0){
          boardTimers[boardIndex][relay]?.cancel();
          boardTimers[boardIndex][relay]=null;
          await _setRelay(b, boardIndex, relay, false);
          _addLog(b,'TIMER','Timer finished R$relay');
        }
      });
    } else {
      b.relayTimers[relay]=0;
    }
    await _save();
  }

  Future<void> _setGroup(Board b, int boardIndex, Group g, bool on, {int? timerSec}) async {
    _addLog(b,'INFO','Group ${g.name} -> ${g.relays.join(', ')} set ${on? 'On':'Off'}');
    for (final r in g.relays){
      if (r>=0 && r<=7){
        await _setRelay(b, boardIndex, r, on, timerSec: timerSec);
        await Future.delayed(const Duration(milliseconds:120));
      }
    }
  }

  Future<void> _startListening(Board b) async {
    final available = await speech.initialize(onStatus: (_) {}, onError: (_) {});
    if (!available){ _addLog(b,'ERROR','Mic not available'); await tts.speak('Microfono non disponibile'); return; }
    setState(()=> isListening=true);
    _addLog(b,'VOICE','Listening...');
    speech.listen(localeId: 'it_IT', onResult: (r){
      if (r.finalResult){
        final text = r.recognizedWords.toLowerCase();
        _addLog(b,'VOICE','Recognized: $text');
        _parseVoice(b, text);
        setState(()=> isListening=false);
      }
    });
  }

  void _stopListening(Board b){ speech.stop(); setState(()=> isListening=false); _addLog(b,'VOICE','Stopped'); }

  void _parseVoice(Board b, String cmd){
    cmd = cmd.toLowerCase();
    if (cmd.contains('accendi tutto')){ final idx = boards.indexOf(b); for(int i=0;i<8;i++) _setRelay(b, idx, i, true); return; }
    if (cmd.contains('spegni tutto')){ final idx = boards.indexOf(b); for(int i=0;i<8;i++) _setRelay(b, idx, i, false); return; }
    for(final g in b.groups){ if (cmd.contains(g.name.toLowerCase())){ final idx=boards.indexOf(b); if (cmd.contains('accendi')){ _setGroup(b, idx, g, true); return;} if (cmd.contains('spegni')){ _setGroup(b, idx, g, false); return;} } }
    final numReg = RegExp(r'\b(\d{1,2})\b'); final m = numReg.firstMatch(cmd);
    if (m!=null){ final n=int.tryParse(m.group(1)!); if (n!=null && n>=0 && n<=7){ final idx=boards.indexOf(b); if (cmd.contains('accendi')) _setRelay(b, idx, n, true); else if (cmd.contains('spegni')) _setRelay(b, idx, n, false); return; } }
    for(int i=0;i<8;i++){ if (cmd.contains(b.relayConfigs[i].name.toLowerCase())){ final idx=boards.indexOf(b); if (cmd.contains('accendi')) _setRelay(b, idx, i, true); else if (cmd.contains('spegni')) _setRelay(b, idx, i, false); return; } }
    _addLog(b,'VOICE','Command not recognized: $cmd'); tts.speak('Comando non riconosciuto');
  }

  Future<int> _askTimer(BuildContext ctx) async {
    int v=0;
    return await showDialog<int>(context: ctx, builder: (_)=> AlertDialog(
      title: const Text('Timer (s, 0 = none)'),
      content: StatefulBuilder(builder: (c,s)=> Column(mainAxisSize: MainAxisSize.min, children: [
        Slider(value: v.toDouble(), min: 0, max: 120, divisions: 120, label: '$v s', onChanged: (val)=> s(()=> v = val.toInt())),
        const SizedBox(height:8),
        Text('$v secondi')
      ])),
      actions: [ TextButton(onPressed: ()=> Navigator.pop(ctx,0), child: const Text('Nessun Timer')), TextButton(onPressed: ()=> Navigator.pop(ctx,v), child: const Text('OK')) ],
    )) ?? 0;
  }

  Future<void> _addBoardDialog() async {
    final nameC=TextEditingController(); final ipC=TextEditingController();
    final res = await showDialog<bool>(context: context, builder: (_)=> AlertDialog(
      title: const Text('Aggiungi scheda'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [ TextField(controller: nameC, decoration: const InputDecoration(labelText: 'Nome')), TextField(controller: ipC, decoration: const InputDecoration(labelText: 'IP (es. http://192.168.1.50)')) ]),
      actions: [ TextButton(onPressed: ()=> Navigator.pop(context,false), child: const Text('Annulla')), TextButton(onPressed: ()=> Navigator.pop(context,true), child: const Text('OK')) ],
    ));
    if (res==true){ final name=nameC.text.trim(); var ip=ipC.text.trim(); if (!ip.startsWith('http')) ip='http://$ip'; if (name.isEmpty||ip.isEmpty) return; setState(()=> boards.add(Board(name: name, ip: ip))); boardTimers.add(List<Timer?>.filled(8,null)); await _save(); }
  }

  Future<void> _editBoardDialog(int idx) async {
    final b = boards[idx];
    final nameC=TextEditingController(text: b.name); final ipC=TextEditingController(text: b.ip);
    final res = await showDialog<bool>(context: context, builder: (_)=> AlertDialog(
      title: const Text('Modifica scheda'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [ TextField(controller: nameC, decoration: const InputDecoration(labelText:'Nome')), TextField(controller: ipC, decoration: const InputDecoration(labelText:'IP (es. http://192.168.1.50)')) ]),
      actions: [ TextButton(onPressed: ()=> Navigator.pop(context,false), child: const Text('Annulla')), TextButton(onPressed: ()=> Navigator.pop(context,true), child: const Text('OK')) ],
    ));
    if (res==true){ var ip = ipC.text.trim(); if (!ip.startsWith('http')) ip='http://$ip'; setState(()=> b.name = nameC.text.trim(); b.ip = ip); await _save(); _addLog(b,'INFO','Scheda modificata'); }
  }

  Future<void> _removeBoard(int idx) async {
    if (boards.length<=1){ ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deve rimanere almeno una scheda'))); return; }
    final name = boards[idx].name; setState(()=> boards.removeAt(idx)); boardTimers.removeAt(idx); await _save(); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Scheda $name rimossa')));
  }

  Future<void> _addGroupDialog(Board b) async {
    final nameC=TextEditingController(); List<bool> sel = List<bool>.filled(8,false);
    final res = await showDialog<bool>(context: context, builder: (_)=> AlertDialog(
      title: const Text('Nuovo gruppo'),
      content: StatefulBuilder(builder: (c,s)=> Column(mainAxisSize: MainAxisSize.min, children: [ TextField(controller: nameC, decoration: const InputDecoration(labelText:'Nome gruppo')), const SizedBox(height:8), Wrap(children: List.generate(8, (i)=> FilterChip(label: Text('R$i'), selected: sel[i], onSelected: (v)=> s(()=> sel[i]=v)))) ])),

      actions: [ TextButton(onPressed: ()=> Navigator.pop(context,false), child: const Text('Annulla')), TextButton(onPressed: ()=> Navigator.pop(context,true), child: const Text('OK')) ],
    ));
    if (res==true){ final name = nameC.text.trim(); final rels=<int>[]; for (int i=0;i<8;i++) if (sel[i]) rels.add(i); if (name.isEmpty||rels.isEmpty) return; setState(()=> b.groups.add(Group(name: name, relays: rels))); _addLog(b,'INFO','Group added $name'); await _save(); }
  }

  Future<void> _editGroupDialog(Board b, Group g) async {
    final nameC=TextEditingController(text: g.name); List<bool> sel = List<bool>.filled(8,false); for (final r in g.relays) if (r>=0&&r<=7) sel[r]=true;
    final res = await showDialog<bool>(context: context, builder: (_)=> AlertDialog(
      title: const Text('Modifica gruppo'),
      content: StatefulBuilder(builder: (c,s)=> Column(mainAxisSize: MainAxisSize.min, children: [ TextField(controller: nameC, decoration: const InputDecoration(labelText: 'Nome gruppo')), const SizedBox(height:8), Wrap(children: List.generate(8, (i)=> FilterChip(label: Text('R$i'), selected: sel[i], onSelected: (v)=> s(()=> sel[i]=v)))) ])),
      actions: [ TextButton(onPressed: ()=> Navigator.pop(context,false), child: const Text('Annulla')), TextButton(onPressed: ()=> Navigator.pop(context,true), child: const Text('OK')) ],
    ));
    if (res==true){ final name = nameC.text.trim(); final rels=<int>[]; for (int i=0;i<8;i++) if (sel[i]) rels.add(i); if (name.isEmpty||rels.isEmpty) return; setState(()=> g.name=name; g.relays=rels); _addLog(b,'INFO','Group edited $name'); await _save(); }
  }

  Future<void> _editRelayName(Board b, int relay) async {
    final ctrl = TextEditingController(text: b.relayConfigs[relay].name);
    final res = await showDialog<bool>(context: context, builder: (_)=> AlertDialog(
      title: Text('Nome relè ${relay}'),
      content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Nome')),
      actions: [ TextButton(onPressed: ()=> Navigator.pop(context,false), child: const Text('Annulla')), TextButton(onPressed: ()=> Navigator.pop(context,true), child: const Text('OK')) ],
    ));
    if (res==true){ setState(()=> b.relayConfigs[relay].name = ctrl.text.trim()); await _save(); _addLog(b,'INFO','Relay name changed ${ctrl.text.trim()}'); }
  }

  Future<String> _exportLogs(Board b) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/${b.name.replaceAll(' ', '_')}_logs_${DateTime.now().toIso8601String().replaceAll(':','-')}.txt');
      final sb = StringBuffer();
      for (final e in b.logs.reversed) sb.writeln('${e['time']} [${e['type']}] ${e['message']}');
      await file.writeAsString(sb.toString());
      _addLog(b,'INFO','Exported logs to ${file.path}');
      return file.path;
    } catch(e){ _addLog(b,'ERROR','Export failed $e'); return ''; }
  }

  void _enterBlackScreen() { Wakelock.enable(); Navigator.push(context, MaterialPageRoute(builder: (_)=> BlackScreen(onExit: (){ Wakelock.disable(); }))); }

  @override
  Widget build(BuildContext context) {
    if (boards.isEmpty) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    tabController = TabController(length: boards.length, vsync: this);
    final idx = tabController.index;
    final board = boards[idx];
    return Scaffold(
      appBar: AppBar(title: const Text('Camar'), bottom: TabBar(controller: tabController, isScrollable: true, tabs: boards.map((b)=> Tab(text: b.name)).toList()),
        actions: [ IconButton(icon: const Icon(Icons.add), onPressed: _addBoardDialog), PopupMenuButton<String>(onSelected: (v){ if (v=='edit') _editBoardDialog(idx); if (v=='remove') _removeBoard(idx); if (v=='export') _exportLogs(board); }, itemBuilder: (_)=> [ const PopupMenuItem(value:'edit', child: Text('Modifica scheda')), const PopupMenuItem(value:'remove', child: Text('Rimuovi scheda')), const PopupMenuItem(value:'export', child: Text('Esporta log')) ]) ]),
      body: TabBarView(controller: tabController, children: boards.map((b)=> _boardView(b)).toList()),
      floatingActionButton: FloatingActionButton(child: Icon(isListening? Icons.mic_off: Icons.mic), onPressed: (){ final b = boards[tabController.index]; isListening? _stopListening(b): _startListening(b); }),
      persistentFooterButtons: [ ElevatedButton.icon(onPressed: _enterBlackScreen, icon: const Icon(Icons.screen_lock_portrait), label: const Text('Modalità Nero')) ],
    );
  }

  Widget _boardView(Board b){
    final boardIndex = boards.indexOf(b);
    return ListView(padding: const EdgeInsets.all(12), children: [
      Text('Scheda: ${b.name} (${b.ip})', style: const TextStyle(fontSize:16)),
      const SizedBox(height:12),
      const Text('Relè', style: TextStyle(fontSize:18, fontWeight: FontWeight.bold)),
      const SizedBox(height:8),
      ...List.generate(8, (i)=> Card(child: ListTile(leading: CircleAvatar(child: Text('$i')), title: Text(b.relayConfigs[i].name), subtitle: b.relayTimers[i]>0? Text('Timer: ${b.relayTimers[i]} s'):null, trailing: Wrap(children: [ IconButton(icon: Icon(b.relayStates[i]? Icons.toggle_on: Icons.toggle_off, size:34, color: b.relayStates[i]? Colors.green: Colors.grey), onPressed: () async { if (!b.relayStates[i]){ final sec = await _askTimer(context); await _setRelay(b, boardIndex, i, true, timerSec: sec);} else { await _setRelay(b, boardIndex, i, false);} }), IconButton(icon: const Icon(Icons.edit), onPressed: () => _editRelayName(b,i)), IconButton(icon: const Icon(Icons.info_outline), onPressed: () => showDialog(context: context, builder: (_)=> AlertDialog(title: Text('Relè $i'), content: Text('Nome: ${b.relayConfigs[i].name}\\nStato: ${b.relayStates[i]? 'ON':'OFF'}\\nTimer: ${b.relayTimers[i]} s'), actions: [ TextButton(onPressed: ()=> Navigator.pop(context), child: const Text('OK')) ]))) ])))),
      const SizedBox(height:12),
      const Text('Gruppi', style: TextStyle(fontSize:18, fontWeight: FontWeight.bold)),
      const SizedBox(height:8),
      ...b.groups.map((g)=> Card(child: ListTile(title: Text(g.name), subtitle: Text('Relè: ${g.relays.join(', ')}'), trailing: Wrap(children: [ IconButton(icon: const Icon(Icons.play_arrow), onPressed: ()=> _setGroup(b, boardIndex, g, true)), IconButton(icon: const Icon(Icons.stop), onPressed: ()=> _setGroup(b, boardIndex, g, false)), IconButton(icon: const Icon(Icons.edit), onPressed: ()=> _editGroupDialog(b,g)), IconButton(icon: const Icon(Icons.delete_forever), onPressed: (){ setState(()=> b.groups.remove(g)); _addLog(b,'INFO','Group removed ${g.name}'); _save(); }) ])))),
      ElevatedButton.icon(onPressed: ()=> _addGroupDialog(b), icon: const Icon(Icons.add), label: const Text('Aggiungi gruppo')),
      const SizedBox(height:12),
      const Text('Log recenti', style: TextStyle(fontSize:18, fontWeight: FontWeight.bold)),
      const SizedBox(height:8),
      SizedBox(height:200, child: ListView(children: b.logs.map((e)=> ListTile(title: Text('[${e['type']}] ${e['message']}'), subtitle: Text('${e['time']}'))).toList())),
      const SizedBox(height:12),
      Row(children: [ ElevatedButton.icon(onPressed: () async { final path = await _exportLogs(b); if (path.isNotEmpty) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Logs exported: $path'))); }, icon: const Icon(Icons.upload_file), label: const Text('Esporta log')), const SizedBox(width:8), ElevatedButton.icon(onPressed: () async { setState(()=> b.logs.clear()); await _save(); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Logs cleared'))); }, icon: const Icon(Icons.delete), label: const Text('Pulisci log')) ]),
      const SizedBox(height:120),
    ]);
  }
}

class BlackScreen extends StatelessWidget {
  final VoidCallback onExit;
  const BlackScreen({super.key, required this.onExit});

  @override Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async { onExit(); return true; },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () { onExit(); Navigator.pop(context); },
        child: Container(color: Colors.black),
      ),
    );
  }
}
