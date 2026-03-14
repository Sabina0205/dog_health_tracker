import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  Hive.registerAdapter(PetRecordAdapter());
  await Hive.openBox<PetRecord>('pet_records');
  runApp(PetHealthTrackerApp());
}

class PetHealthTrackerApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pet Health Tracker',
      theme: ThemeData(primarySwatch: Colors.teal),
      home: PetTypeSelectionScreen(),
    );
  }
}

class PetTypeSelectionScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Vyber typ psa')),
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                child: Text('Šteniatko'),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => HomeScreen(isPuppy: true)),
                  );
                },
              ),
              SizedBox(height: 20),
              ElevatedButton(
                child: Text('Dospelý pes'),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => HomeScreen(isPuppy: false)),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final bool isPuppy;
  HomeScreen({required this.isPuppy});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Box<PetRecord> box;

  final List<PetRecord> puppyTemplate = [
    PetRecord(name: 'Očkovanie DHPPi 1', lastDate: DateTime.now(), intervalDays: 21),
    PetRecord(name: 'Očkovanie DHPPi 2', lastDate: DateTime.now().add(Duration(days: 21)), intervalDays: 21),
    PetRecord(name: 'Očkovanie DHPPi 3', lastDate: DateTime.now().add(Duration(days: 42)), intervalDays: 365),
    PetRecord(name: 'Odčervenie 1', lastDate: DateTime.now(), intervalDays: 14),
    PetRecord(name: 'Odčervenie 2', lastDate: DateTime.now().add(Duration(days: 14)), intervalDays: 14),
    PetRecord(name: 'Bordetella', lastDate: DateTime.now(), intervalDays: 365),
  ];

  @override
  void initState() {
    super.initState();
    box = Hive.box<PetRecord>('pet_records');
    if (widget.isPuppy && box.isEmpty) {
      for (var record in puppyTemplate) {
        box.add(record);
      }
    }
  }

  int getCompletedCount() {
    int count = 0;
    for (var record in box.values) {
      if (record.isDone) count++;
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Pet Health Tracker')),
      body: ValueListenableBuilder(
        valueListenable: box.listenable(),
        builder: (context, Box<PetRecord> records, _) {
          if (records.isEmpty) return Center(child: Text('Žiadne záznamy'));

          int completed = getCompletedCount();
          double progress = records.length > 0 ? completed / records.length : 0;

          return Column(
            children: [
              Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Pokrok očkovania šteniatka:', style: TextStyle(fontSize: 16)),
                    SizedBox(height: 8),
                    LinearProgressIndicator(value: progress),
                    SizedBox(height: 8),
                    Text('${completed} / ${records.length} dokončené'),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: records.length,
                  itemBuilder: (context, index) {
                    final record = records.getAt(index);
                    if (record == null) return SizedBox();

                    final nextDate = record.lastDate.add(Duration(days: record.intervalDays));
                    return Card(
                      child: ListTile(
                        title: Text(record.name),
                        subtitle: Text('Ďalšia dávka: ${nextDate.toLocal().toString().split(' ')[0]}'),
                        trailing: Checkbox(
                          value: record.isDone,
                          onChanged: (val) {
                            setState(() {
                              record.isDone = val ?? false;
                              record.save();
                            });
                          },
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => RecordDetailScreen(record: record)),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class RecordDetailScreen extends StatelessWidget {
  final PetRecord record;
  RecordDetailScreen({required this.record});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(record.name)),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Posledný dátum: ${record.lastDate.toLocal().toString().split(' ')[0]}'),
            SizedBox(height: 8),
            Text('Interval dní: ${record.intervalDays}'),
            SizedBox(height: 8),
            Text('Poznámky:'),
            TextField(
              controller: TextEditingController(text: record.notes),
              maxLines: 3,
              onChanged: (val) {
                record.notes = val;
                record.save();
              },
              decoration: InputDecoration(border: OutlineInputBorder()),
            ),
          ],
        ),
      ),
    );
  }
}


@HiveType(typeId: 0)
class PetRecord extends HiveObject {
  @HiveField(0)
  String name;

  @HiveField(1)
  DateTime lastDate;

  @HiveField(2)
  int intervalDays;

  @HiveField(3)
  bool isDone;

  @HiveField(4)
  String notes;

  PetRecord({required this.name, required this.lastDate, required this.intervalDays, this.isDone = false, this.notes = ''});
}

class PetRecordAdapter extends TypeAdapter<PetRecord> {
  @override
  final typeId = 0;

  @override
  PetRecord read(BinaryReader reader) {
    return PetRecord(
      name: reader.readString(),
      lastDate: reader.read() as DateTime? ?? DateTime.now(),
      intervalDays: reader.readInt(),
      isDone: reader.read() as bool? ?? false,
      notes: reader.read() as String? ?? '',
    );
  }

  @override
  void write(BinaryWriter writer, PetRecord obj) {
    writer.writeString(obj.name);
    writer.write(obj.lastDate);
    writer.writeInt(obj.intervalDays);
    writer.write(obj.isDone);
    writer.write(obj.notes);
  }
}
