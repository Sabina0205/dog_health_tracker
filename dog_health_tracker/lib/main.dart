import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const DogHealthTrackerApp());
}

class DogHealthTrackerApp extends StatelessWidget {
  const DogHealthTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dog Health Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0C8A7C),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF2F8F7),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0xFFE2EFEC)),
          ),
        ),
      ),
      home: const PetHealthHomePage(),
    );
  }
}

enum DogType { puppy, adult }

enum ProcedureType { vaccination, deworming, medication, checkup, other }

enum RecordFilter { upcoming, all, completed }

enum RepeatUnit { days, weeks, months }

class HealthRecord {
  HealthRecord({
    required this.title,
    required this.type,
    required this.date,
    this.completed = false,
    this.note = '',
  });

  String title;
  ProcedureType type;
  DateTime date;
  bool completed;
  String note;

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'type': type.name,
      'date': date.toIso8601String(),
      'completed': completed,
      'note': note,
    };
  }

  static HealthRecord fromMap(Map<String, dynamic> map) {
    return HealthRecord(
      title: map['title'] as String? ?? '',
      type: _procedureTypeFromName(map['type'] as String?),
      date: DateTime.tryParse(map['date'] as String? ?? '') ?? DateTime.now(),
      completed: map['completed'] as bool? ?? false,
      note: map['note'] as String? ?? '',
    );
  }
}

class DogProfile {
  DogProfile({
    required this.id,
    required this.name,
    required this.type,
    this.birthDate,
    this.lastVaccinationDate,
    this.weightKg,
    this.photoUrl,
    List<HealthRecord>? records,
  }) : records = records ?? [];

  final String id;
  String name;
  DogType type;
  DateTime? birthDate;
  DateTime? lastVaccinationDate;
  double? weightKg;
  String? photoUrl;
  final List<HealthRecord> records;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type.name,
      'birthDate': birthDate?.toIso8601String(),
      'lastVaccinationDate': lastVaccinationDate?.toIso8601String(),
      'weightKg': weightKg,
      'photoUrl': photoUrl,
      'records': records.map((record) => record.toMap()).toList(),
    };
  }

  static DogProfile fromMap(Map<String, dynamic> map) {
    final recordItems = map['records'] as List<dynamic>? ?? [];
    return DogProfile(
      id: map['id'] as String,
      name: map['name'] as String? ?? 'Pes',
      type: _dogTypeFromName(map['type'] as String?),
      birthDate: DateTime.tryParse(map['birthDate'] as String? ?? ''),
      lastVaccinationDate:
          DateTime.tryParse(map['lastVaccinationDate'] as String? ?? ''),
      weightKg: _doubleFromDynamic(map['weightKg']),
      photoUrl: map['photoUrl'] as String?,
      records: recordItems
          .map((item) => HealthRecord.fromMap(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

class _DogDraftWithType {
  _DogDraftWithType({
    required this.type,
    required this.name,
    required this.date,
    this.weightKg,
    this.photoUrl,
    this.lastDewormingDate,
    this.birthDate,
  });

  final DogType type;
  final String name;
  final DateTime date;
  final double? weightKg;
  final String? photoUrl;
  final DateTime? lastDewormingDate;
  final DateTime? birthDate;
}

class _RecordDraft {
  _RecordDraft({
    required this.title,
    required this.type,
    required this.date,
    required this.note,
    this.repeatValue,
    this.repeatUnit,
  });

  final String title;
  final ProcedureType type;
  final DateTime date;
  final String note;
  final int? repeatValue;
  final RepeatUnit? repeatUnit;
}

ProcedureType _procedureTypeFromName(String? value) {
  return ProcedureType.values.firstWhere(
    (type) => type.name == value,
    orElse: () => ProcedureType.other,
  );
}

DogType _dogTypeFromName(String? value) {
  return DogType.values.firstWhere(
    (type) => type.name == value,
    orElse: () => DogType.adult,
  );
}

double? _doubleFromDynamic(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value.toString());
}

class PetHealthHomePage extends StatefulWidget {
  const PetHealthHomePage({super.key});

  @override
  State<PetHealthHomePage> createState() => _PetHealthHomePageState();
}

class _PetHealthHomePageState extends State<PetHealthHomePage> {
  static const MethodChannel _storageChannel = MethodChannel(
    'pet_health/storage',
  );

  static const String _annualRevaccinationTitle = 'Preočkovanie po roku';
  static const String _autoDewormingNote = '__auto_deworming__';
  static const String _autoReminderNote = '__auto_reminder__';
  static const String _puppyTemplateNote = '__puppy_template__';

  bool _isLoading = true;
  final List<DogProfile> _dogs = [];
  String? _selectedDogId;
  RecordFilter _recordFilter = RecordFilter.all;
  ProcedureType? _filterProcedureType;

  DogProfile? get _selectedDog {
    if (_dogs.isEmpty) {
      return null;
    }
    return _dogs.firstWhere(
      (dog) => dog.id == _selectedDogId,
      orElse: () => _dogs.first,
    );
  }

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _loadStateFromAndroid();
    await _requestNativeNotificationPermission();
    await _scheduleNativeNotifications();
    if (!mounted) {
      return;
    }
    setState(() {
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_dogs.isEmpty) {
      return _buildOnboarding();
    }

    return _buildDashboard();
  }

  Widget _buildOnboarding() {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFE7F7F4), Color(0xFFF9FCFB)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 28),
                const Icon(Icons.pets, size: 62, color: Color(0xFF0C8A7C)),
                const SizedBox(height: 16),
                Text(
                  'Dog Health Tracker',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.1,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Vyber typ psa pri prvom spustení aplikácie.',
                  textAlign: TextAlign.center,
                ),
                const Spacer(),
                _buildChoiceCard(
                  icon: Icons.child_care,
                  title: 'Mám šteniatko',
                  subtitle: 'Nastaví sa plán podľa dátumu narodenia.',
                  onTap: () => _addDogFlow(fixedType: DogType.puppy),
                  filled: true,
                ),
                const SizedBox(height: 12),
                _buildChoiceCard(
                  icon: Icons.pets_outlined,
                  title: 'Mám dospelého psa',
                  subtitle: 'Vyberieš dátum posledného očkovania.',
                  onTap: () => _addDogFlow(fixedType: DogType.adult),
                  filled: false,
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChoiceCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required bool filled,
  }) {
    final color = Theme.of(context).colorScheme;
    return Material(
      color: filled ? color.primary : Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: filled
                    ? Colors.white.withValues(alpha: 0.24)
                    : color.primaryContainer,
                child: Icon(icon, color: filled ? Colors.white : color.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: filled ? Colors.white : color.onSurface,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: filled
                            ? Colors.white.withValues(alpha: 0.9)
                            : const Color(0xFF5E6E6B),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 18,
                color: filled ? Colors.white : color.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDashboard() {
    final dog = _selectedDog!;
    final today = _dateOnly(DateTime.now());
    final pending = dog.records.where((item) => !item.completed).toList();
    final upcoming =
        pending.where((item) => !item.date.isBefore(today)).toList()
          ..sort((a, b) => a.date.compareTo(b.date));
    final allSorted = [...dog.records]
      ..sort((a, b) => a.date.compareTo(b.date));
    final nextAnnualVaccination = _nextAnnualVaccinationDate(dog);
    final completed = allSorted.where((record) => record.completed).toList();
    final baseRecords = switch (_recordFilter) {
      RecordFilter.upcoming => upcoming,
      RecordFilter.completed => completed,
      RecordFilter.all => allSorted,
    };
    final displayedRecords = _filterProcedureType == null
        ? baseRecords
        : baseRecords
            .where((r) => r.type == _filterProcedureType)
            .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dog Health Tracker'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 90),
        children: [
          _buildDogSelector(),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                colors: [Color(0xFF0C8A7C), Color(0xFF4ABAAE)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _buildDogAvatar(dog, radius: 26, onPrimary: true),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            dog.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            _dogTypeLabel(dog.type),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, color: Colors.white),
                      onSelected: (value) {
                        if (value == 'edit') {
                          _editDogProfileFlow(dog);
                        } else if (value == 'delete') {
                          _deleteDogFlow(dog);
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'edit',
                          child: Text('Upraviť'),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(
                            'Vymazať psa',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                if (dog.birthDate != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Dátum narodenia: ${_formatDate(dog.birthDate!)} (${_formatAgeSk(dog.birthDate!)})',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.92),
                    ),
                  ),
                ],
                if (dog.weightKg != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Váha: ${dog.weightKg!.toStringAsFixed(1)} kg',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.92),
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  nextAnnualVaccination == null
                      ? 'Najbližšie preočkovanie: zatiaľ nie je nastavené'
                      : 'Najbližšie preočkovanie: ${_formatDate(nextAnnualVaccination)}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.95),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _infoPill('Úkony spolu', '${dog.records.length}'),
                    _infoPill('Čakajúce', '${pending.length}'),
                    _infoPill('Nadchádzajúce', '${upcoming.length}'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Nadchádzajúce povinnosti',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.event_note),
              title: Text(
                upcoming.isEmpty
                    ? 'Nemáš naplánované žiadne úkony.'
                    : 'Máš ${upcoming.length} naplánovaných úkonov.',
              ),
              subtitle: const Text(
                'Sleduj termíny očkovaní, odčervení a liečby.',
              ),
            ),
          ),
          if (upcoming.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 112,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: upcoming.length > 5 ? 5 : upcoming.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final record = upcoming[index];
                  return SizedBox(
                    width: 220,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              record.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(_labelForType(record.type)),
                            const Spacer(),
                            Text(
                              _formatDate(record.date),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                'Zdravotné záznamy',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 8),
              Text(
                '${displayedRecords.length} položiek',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Nadchádzajúce'),
                selected: _recordFilter == RecordFilter.upcoming,
                onSelected: (_) {
                  setState(() {
                    _recordFilter = RecordFilter.upcoming;
                  });
                },
              ),
              ChoiceChip(
                label: const Text('Všetky'),
                selected: _recordFilter == RecordFilter.all,
                onSelected: (_) {
                  setState(() {
                    _recordFilter = RecordFilter.all;
                  });
                },
              ),
              ChoiceChip(
                label: const Text('Splnené'),
                selected: _recordFilter == RecordFilter.completed,
                onSelected: (_) {
                  setState(() {
                    _recordFilter = RecordFilter.completed;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<ProcedureType?>(
            initialValue: _filterProcedureType,
            decoration: const InputDecoration(
              labelText: 'Filtrovať podľa typu',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            items: [
              const DropdownMenuItem(
                value: null,
                child: Text('Všetky typy'),
              ),
              ...ProcedureType.values.map(
                (type) => DropdownMenuItem(
                  value: type,
                  child: Text(_labelForType(type)),
                ),
              ),
            ],
            onChanged: (value) {
              setState(() {
                _filterProcedureType = value;
              });
            },
          ),
          const SizedBox(height: 10),
          if (displayedRecords.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Center(
                  child: Text('Pre tento filter nie sú žiadne záznamy.'),
                ),
              ),
            )
          else
            ...displayedRecords.map((record) {
              final isOverdue =
                  !record.completed && _dateOnly(record.date).isBefore(today);
              final statusText = record.completed
                  ? 'Splnené'
                  : isOverdue
                      ? 'Oneskorené'
                      : 'Čaká';
              final statusColor = record.completed
                  ? Colors.green
                  : isOverdue
                      ? Colors.red
                      : const Color(0xFF0C8A7C);

              return Card(
                child: InkWell(
                  onTap: () => _editRecordDialog(dog, record),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          _iconForType(record.type),
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      record.title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: statusColor
                                          .withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      statusText,
                                      style: TextStyle(
                                        color: statusColor,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${_labelForType(record.type)} • ${_formatDate(record.date)}',
                                style:
                                    Theme.of(context).textTheme.bodySmall,
                              ),
                              if (_shouldShowNote(record.note)) ...[
                                const SizedBox(height: 4),
                                Text(record.note),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          children: [
                            Checkbox(
                              value: record.completed,
                              onChanged: (value) {
                                setState(() {
                                  record.completed = value ?? false;
                                  _recalculateLastVaccination(dog);
                                });
                                _persist();
                              },
                            ),
                            IconButton(
                              tooltip: 'Zmazať záznam',
                              onPressed: () => _deleteRecord(dog, record),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addRecordDialog,
        icon: const Icon(Icons.add),
        label: const Text('Pridať úkon'),
      ),
    );
  }

  Widget _buildDogSelector() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.pets, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Moji psíci',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Pridať psa',
                  icon: const Icon(Icons.add),
                  onPressed: _addDogFlow,
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 84,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _dogs.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final dog = _dogs[index];
                  final isSelected = dog.id == _selectedDogId;
                  return InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      setState(() {
                        _selectedDogId = dog.id;
                      });
                      _persist();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 156,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: isSelected
                            ? const Color(0xFFE0F4F1)
                            : Colors.grey.shade50,
                        border: Border.all(
                          color: isSelected
                              ? Theme.of(context).colorScheme.primary
                              : const Color(0xFFDCE8E5),
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          _buildDogAvatar(
                            dog,
                            radius: 20,
                            onPrimary: isSelected,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  dog.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _dogTypeLabel(dog.type),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoPill(String title, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        '$title: $value',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Future<void> _addDogFlow({DogType? fixedType}) async {
    final draft = await _openAddDogPage(fixedType: fixedType);
    if (!mounted || draft == null) {
      return;
    }

    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final resolvedName =
        draft.name.isEmpty ? 'Pes ${_dogs.length + 1}' : draft.name;
    var selectedDate = _dateOnly(draft.date);
    if (draft.type == DogType.adult) {
      selectedDate = await _resolveAdultVaccinationDate(selectedDate);
      if (!mounted) {
        return;
      }
    }
    final dog = draft.type == DogType.puppy
        ? _createPuppyDog(
            id: id,
            name: resolvedName,
            birthDate: selectedDate,
            weightKg: draft.weightKg,
            photoUrl: draft.photoUrl,
          )
        : _createAdultDog(
            id: id,
            name: resolvedName,
            lastVaccinationDate: selectedDate,
            weightKg: draft.weightKg,
            photoUrl: draft.photoUrl,
            lastDewormingDate: draft.lastDewormingDate,
            birthDate: draft.birthDate,
          );

    setState(() {
      _dogs.add(dog);
      _selectedDogId = dog.id;
    });
    _persist();
  }

  Future<DateTime> _resolveAdultVaccinationDate(DateTime selectedDate) async {
    if (!_isVaccinationExpired(selectedDate)) {
      return selectedDate;
    }

    final useNewDate = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Očkovanie je prepadnuté'),
        content: Text(
          'Posledné očkovanie (${_formatDate(selectedDate)}) je staršie ako 1 rok. '
          'Odporúčame doplniť nový dátum očkovania.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Ponechať dátum'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Doplniť dátum'),
          ),
        ],
      ),
    );

    if (useNewDate != true || !mounted) {
      return selectedDate;
    }

    final today = _dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: today,
      firstDate: selectedDate,
      lastDate: today,
      helpText: 'Dátum doplneného očkovania',
    );
    if (picked == null) {
      return selectedDate;
    }
    return _dateOnly(picked);
  }

  bool _isVaccinationExpired(DateTime lastVaccinationDate) {
    final nextDue = _annualFrom(lastVaccinationDate);
    final today = _dateOnly(DateTime.now());
    return !nextDue.isAfter(today);
  }

  Widget _buildDogAvatar(
    DogProfile dog, {
    required double radius,
    required bool onPrimary,
  }) {
    final backgroundColor = onPrimary
        ? Colors.white.withValues(alpha: 0.24)
        : Theme.of(context).colorScheme.primaryContainer;
    final iconColor = onPrimary
        ? Colors.white
        : Theme.of(context).colorScheme.primary;

    final url = dog.photoUrl?.trim();
    if (url != null && url.isNotEmpty) {
      final isHttp = url.startsWith('http://') || url.startsWith('https://');
      return CircleAvatar(
        radius: radius,
        backgroundColor: backgroundColor,
        backgroundImage: isHttp
            ? NetworkImage(url)
            : FileImage(File(url)) as ImageProvider<Object>,
        onBackgroundImageError: (_, __) {},
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor,
      child: Icon(_dogTypeIcon(dog.type), color: iconColor, size: radius + 2),
    );
  }

  Future<void> _editDogProfileFlow(DogProfile dog) async {
    final nameController = TextEditingController(text: dog.name);
    final weightController = TextEditingController(
      text: dog.weightKg?.toString() ?? '',
    );
    final photoController = TextEditingController(text: dog.photoUrl ?? '');
    DateTime? selectedBirthDate = dog.birthDate;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Upraviť profil psa'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Meno psa'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: weightController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Váha (kg)'),
                ),
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Dátum narodenia'),
                  subtitle: Text(
                    selectedBirthDate != null
                        ? _formatDate(selectedBirthDate!)
                        : 'Nenastavený',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (selectedBirthDate != null)
                        IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          tooltip: 'Odstrániť dátum narodenia',
                          onPressed: () {
                            setDialogState(() {
                              selectedBirthDate = null;
                            });
                          },
                        ),
                      const Icon(Icons.cake_outlined, size: 18),
                    ],
                  ),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedBirthDate ?? DateTime.now(),
                      firstDate: DateTime(2010),
                      lastDate: DateTime.now(),
                    );
                    if (picked == null || !context.mounted) return;
                    setDialogState(() {
                      selectedBirthDate = DateTime(
                        picked.year,
                        picked.month,
                        picked.day,
                      );
                    });
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: photoController,
                  decoration: const InputDecoration(
                    labelText: 'Cesta/URL fotky (voliteľné)',
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () async {
                      final picked = await _pickDogPhotoFromPhone();
                      if (picked == null || !context.mounted) {
                        return;
                      }
                      setDialogState(() {
                        photoController.text = picked;
                      });
                    },
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Vybrať fotku z telefónu'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Zrušiť'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Uložiť'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) {
      nameController.dispose();
      weightController.dispose();
      photoController.dispose();
      return;
    }

    final parsedWeight = _doubleFromDynamic(
      weightController.text.trim().replaceAll(',', '.'),
    );
    final trimmedName = nameController.text.trim();
    final trimmedPhoto = photoController.text.trim();

    setState(() {
      dog.name = trimmedName.isEmpty ? dog.name : trimmedName;
      dog.weightKg = parsedWeight;
      dog.photoUrl = trimmedPhoto.isEmpty ? null : trimmedPhoto;
      dog.birthDate = selectedBirthDate;
    });
    _persist();

    nameController.dispose();
    weightController.dispose();
    photoController.dispose();
  }

  Future<String?> _pickDogPhotoFromPhone() async {
    try {
      return await _storageChannel.invokeMethod<String>('pickDogPhoto');
    } catch (_) {
      return null;
    }
  }

  Future<void> _deleteDogFlow(DogProfile dog) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Vymazať psa?'),
        content: Text('Naozaj chceš vymazať profil psa "${dog.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Zrušiť'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Vymazať'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _dogs.removeWhere((item) => item.id == dog.id);
      if (_dogs.isEmpty) {
        _selectedDogId = null;
      } else if (_selectedDogId == dog.id) {
        _selectedDogId = _dogs.first.id;
      }
    });
    _persist();
  }

  Future<_DogDraftWithType?> _openAddDogPage({DogType? fixedType}) async {
    return Navigator.of(context).push<_DogDraftWithType>(
      MaterialPageRoute(builder: (_) => AddDogPage(fixedType: fixedType)),
    );
  }

  DogProfile _createPuppyDog({
    required String id,
    required String name,
    required DateTime birthDate,
    double? weightKg,
    String? photoUrl,
  }) {
    final firstVaccination = birthDate.add(const Duration(days: 42));
    final secondVaccination = birthDate.add(const Duration(days: 63));
    final thirdVaccination = birthDate.add(const Duration(days: 84));
    final records = <HealthRecord>[];

    const puppyDewormingWeeks = [2, 4, 6, 8, 11];
    for (final week in puppyDewormingWeeks) {
      records.add(
        HealthRecord(
          title: 'Odčervenie - $week. týždeň',
          type: ProcedureType.deworming,
          date: birthDate.add(Duration(days: week * 7)),
          note: _puppyTemplateNote,
        ),
      );
    }

    records.addAll([
      HealthRecord(
        title: '1. vakcinácia (koniec 6. týždňa)',
        type: ProcedureType.vaccination,
        date: firstVaccination,
        note: _puppyTemplateNote,
      ),
      HealthRecord(
        title: '2. vakcinácia (9. týždeň)',
        type: ProcedureType.vaccination,
        date: secondVaccination,
        note: _puppyTemplateNote,
      ),
      HealthRecord(
        title: '3. vakcinácia (12. týždeň)',
        type: ProcedureType.vaccination,
        date: thirdVaccination,
        note: _puppyTemplateNote,
      ),
    ]);

    for (var monthOffset = 4; monthOffset <= 8; monthOffset++) {
      records.add(
        HealthRecord(
          title: 'Odčervenie - $monthOffset. mesiac',
          type: ProcedureType.deworming,
          date: DateTime(
            birthDate.year,
            birthDate.month + monthOffset,
            birthDate.day,
          ),
          note: _puppyTemplateNote,
        ),
      );
    }

    for (var monthOffset = 11; monthOffset <= 24; monthOffset += 3) {
      records.add(
        HealthRecord(
          title: 'Odčervenie - každé 3 mesiace',
          type: ProcedureType.deworming,
          date: DateTime(
            birthDate.year,
            birthDate.month + monthOffset,
            birthDate.day,
          ),
          note: _puppyTemplateNote,
        ),
      );
    }

    final dog = DogProfile(
      id: id,
      name: name,
      type: DogType.puppy,
      birthDate: birthDate,
      lastVaccinationDate: thirdVaccination,
      weightKg: weightKg,
      photoUrl: photoUrl,
      records: records,
    );
    _syncAnnualRevaccinationRecord(dog);
    _syncPreVaccinationDewormingRecords(dog);
    _syncReminderRecords(dog);
    return dog;
  }

  DogProfile _createAdultDog({
    required String id,
    required String name,
    required DateTime lastVaccinationDate,
    double? weightKg,
    String? photoUrl,
    DateTime? lastDewormingDate,
    DateTime? birthDate,
  }) {
    final records = <HealthRecord>[
      HealthRecord(
        title: 'Posledné očkovanie',
        type: ProcedureType.vaccination,
        date: lastVaccinationDate,
        completed: true,
      ),
    ];

    if (lastDewormingDate != null) {
      records.add(
        HealthRecord(
          title: 'Posledné odčervenie',
          type: ProcedureType.deworming,
          date: _dateOnly(lastDewormingDate),
          completed: true,
        ),
      );
      for (var monthOffset = 3; monthOffset <= 24; monthOffset += 3) {
        records.add(
          HealthRecord(
            title: 'Odčervenie (každé 3 mesiace)',
            type: ProcedureType.deworming,
            date: DateTime(
              lastDewormingDate.year,
              lastDewormingDate.month + monthOffset,
              lastDewormingDate.day,
            ),
          ),
        );
      }
    }

    final dog = DogProfile(
      id: id,
      name: name,
      type: DogType.adult,
      birthDate: birthDate,
      lastVaccinationDate: lastVaccinationDate,
      weightKg: weightKg,
      photoUrl: photoUrl,
      records: records,
    );
    _syncAnnualRevaccinationRecord(dog);
    _syncPreVaccinationDewormingRecords(dog);
    _syncReminderRecords(dog);
    return dog;
  }

  Future<void> _addRecordDialog() async {
    final dog = _selectedDog;
    if (dog == null) {
      return;
    }
    final draft = await Navigator.of(context).push<_RecordDraft>(
      MaterialPageRoute(builder: (_) => const AddRecordPage()),
    );
    if (!mounted || draft == null) {
      return;
    }

    setState(() {
      dog.records.add(
        HealthRecord(
          title: draft.title,
          type: draft.type,
          date: _dateOnly(draft.date),
          note: draft.note,
        ),
      );
      if (draft.type == ProcedureType.vaccination) {
        _updateLastVaccination(dog, draft.date);
      }
      if (draft.repeatValue != null &&
          draft.repeatValue! > 0 &&
          draft.repeatUnit != null) {
        final followUpDate = _dateOnly(
          _calculateRepeatDate(
            draft.date,
            draft.repeatValue!,
            draft.repeatUnit!,
          ),
        );
        final followUpTitle = draft.type == ProcedureType.vaccination
            ? 'Preočkovanie: ${draft.title}'
            : 'Opakovanie: ${draft.title}';
        dog.records.add(
          HealthRecord(
            title: followUpTitle,
            type: draft.type,
            date: followUpDate,
          ),
        );
      }
      _syncPreVaccinationDewormingRecords(dog);
      _syncReminderRecords(dog);
    });
    _persist();
  }

  Future<void> _editRecordDialog(DogProfile dog, HealthRecord record) async {
    final titleController = TextEditingController(text: record.title);
    final noteController = TextEditingController(text: record.note);
    DateTime selectedDate = record.date;
    ProcedureType selectedType = record.type;

    // Zisti ci uz existuje follow-up zaznam a predvyplni opakovanie
    final vacPrefix = 'Preočkovanie: ${record.title}';
    final repPrefix = 'Opakovanie: ${record.title}';
    final existingFollowUp = dog.records.firstWhere(
      (r) => r.title == vacPrefix || r.title == repPrefix,
      orElse: () => HealthRecord(
        title: '',
        type: record.type,
        date: record.date,
      ),
    );
    final hasFollowUp = existingFollowUp.title.isNotEmpty;

    bool repeatEnabled = hasFollowUp;
    final repeatValueController = TextEditingController();
    RepeatUnit repeatUnit = RepeatUnit.months;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Upraviť úkon'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: 'Názov úkonu'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<ProcedureType>(
                  initialValue: selectedType,
                  decoration: const InputDecoration(labelText: 'Typ'),
                  items: ProcedureType.values
                      .map(
                        (type) => DropdownMenuItem(
                          value: type,
                          child: Text(_labelForType(type)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(() {
                      selectedType = value;
                    });
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: noteController,
                  decoration: const InputDecoration(
                    labelText: 'Poznámka (voliteľná)',
                  ),
                ),
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Dátum úkonu'),
                  subtitle: Text(_formatDate(selectedDate)),
                  trailing:
                      const Icon(Icons.calendar_today_outlined, size: 18),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(2010),
                      lastDate: DateTime(2100),
                    );
                    if (picked == null || !context.mounted) return;
                    setDialogState(() {
                      selectedDate = DateTime(
                        picked.year,
                        picked.month,
                        picked.day,
                      );
                    });
                  },
                ),
                const SizedBox(height: 4),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Opakovať úkon'),
                  subtitle: Text(
                    hasFollowUp
                        ? 'Existujúci follow-up bude aktualizovaný'
                        : 'Vytvorí sa nový follow-up záznam',
                    style: const TextStyle(fontSize: 12),
                  ),
                  value: repeatEnabled,
                  onChanged: (value) {
                    setDialogState(() {
                      repeatEnabled = value;
                    });
                  },
                ),
                if (repeatEnabled) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: repeatValueController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Počet',
                            hintText: 'napr. 3',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<RepeatUnit>(
                          initialValue: repeatUnit,
                          decoration:
                              const InputDecoration(labelText: 'Jednotka'),
                          items: const [
                            DropdownMenuItem(
                              value: RepeatUnit.days,
                              child: Text('dni'),
                            ),
                            DropdownMenuItem(
                              value: RepeatUnit.weeks,
                              child: Text('týždne'),
                            ),
                            DropdownMenuItem(
                              value: RepeatUnit.months,
                              child: Text('mesiace'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setDialogState(() {
                              repeatUnit = value;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Príklad: 6 týždňov alebo 12 mesiacov.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Zrušiť'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Uložiť'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) {
      titleController.dispose();
      noteController.dispose();
      repeatValueController.dispose();
      return;
    }

    final newTitle = titleController.text.trim();
    final newNote = noteController.text.trim();
    final oldDate = record.date;
    final oldTitle = record.title;
    final repeatVal = int.tryParse(repeatValueController.text.trim());

    titleController.dispose();
    noteController.dispose();
    repeatValueController.dispose();

    setState(() {
      record.title = newTitle.isEmpty ? record.title : newTitle;
      record.type = selectedType;
      record.date = _dateOnly(selectedDate);
      record.note = newNote;

      _recalculateLinkedRecords(dog, oldTitle, oldDate, record);

      // Sprav opakovanie
      if (repeatEnabled && repeatVal != null && repeatVal > 0) {
        final followUpDate = _dateOnly(
          _calculateRepeatDate(record.date, repeatVal, repeatUnit),
        );
        final followUpTitle = record.type == ProcedureType.vaccination
            ? 'Preočkovanie: ${record.title}'
            : 'Opakovanie: ${record.title}';

        // Ak uz existuje follow-up (pod starym alebo novym nazvom), aktualizuj ho
        final existingIdx = dog.records.indexWhere(
          (r) =>
              r.title == 'Preočkovanie: $oldTitle' ||
              r.title == 'Opakovanie: $oldTitle' ||
              r.title == 'Preočkovanie: ${record.title}' ||
              r.title == 'Opakovanie: ${record.title}',
        );
        if (existingIdx != -1) {
          final old = dog.records[existingIdx];
          dog.records[existingIdx] = HealthRecord(
            title: followUpTitle,
            type: record.type,
            date: followUpDate,
            completed: old.completed,
            note: old.note,
          );
        } else {
          dog.records.add(
            HealthRecord(
              title: followUpTitle,
              type: record.type,
              date: followUpDate,
            ),
          );
        }
      } else if (!repeatEnabled && hasFollowUp) {
        // Switch vypnuty a followup existoval -> odstran ho
        dog.records.removeWhere(
          (r) =>
              r.title == 'Preočkovanie: $oldTitle' ||
              r.title == 'Opakovanie: $oldTitle' ||
              r.title == 'Preočkovanie: ${record.title}' ||
              r.title == 'Opakovanie: ${record.title}',
        );
      }

      _recalculateLastVaccination(dog);
    });
    _persist();
  }

  /// Prepočíta všetky nadviazané záznamy po editácii úkonu:
  /// 1. Manuálne follow-upy (prefix "Preočkovanie: " / "Opakovanie: ")
  /// 2. Séria odčervení dospelého psa ("Odčervenie (každé 3 mesiace)")
  /// 3. Šablónové záznamy šteniatka (__puppy_template__)
  void _recalculateLinkedRecords(
    DogProfile dog,
    String oldTitle,
    DateTime oldDate,
    HealthRecord editedRecord,
  ) {
    final daysDiff = editedRecord.date.difference(oldDate).inDays;
    final titleChanged = editedRecord.title != oldTitle;

    // 1. Manuálne follow-upy s prefixom Preočkovanie:/Opakovanie:
    if (daysDiff != 0 || titleChanged) {
      final prefixes = ['Preočkovanie: ', 'Opakovanie: '];
      for (final prefix in prefixes) {
        final followUpTitle = '$prefix$oldTitle';
        final idx = dog.records.indexWhere((r) => r.title == followUpTitle);
        if (idx != -1) {
          final old = dog.records[idx];
          dog.records[idx] = HealthRecord(
            title: '$prefix${editedRecord.title}',
            type: old.type,
            date: _dateOnly(old.date.add(Duration(days: daysDiff))),
            completed: old.completed,
            note: old.note,
          );
        }
      }
    }

    // 2. Dospelý pes - séria odčervení
    if (daysDiff != 0 && dog.type == DogType.adult) {
      const dewSeriesTitle = 'Odčervenie (každé 3 mesiace)';
      const lastDewTitle = 'Posledné odčervenie';

      if (oldTitle == lastDewTitle) {
        // Zmenil sa základný dátum odčervenia -> vymaž a vygeneruj znovu
        dog.records.removeWhere(
          (r) => r.title == dewSeriesTitle && !r.completed,
        );
        final newBase = editedRecord.date;
        for (var monthOffset = 3; monthOffset <= 24; monthOffset += 3) {
          dog.records.add(
            HealthRecord(
              title: dewSeriesTitle,
              type: ProcedureType.deworming,
              date: _dateOnly(
                DateTime(
                  newBase.year,
                  newBase.month + monthOffset,
                  newBase.day,
                ),
              ),
            ),
          );
        }
      } else if (oldTitle == dewSeriesTitle) {
        // Zmenil sa jeden záznam v sérii -> posuň všetky nasledujúce nesplnené
        final seriesRecords = dog.records
            .where((r) => r.title == dewSeriesTitle && !r.completed)
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));

        final editedIdx = seriesRecords.indexWhere(
          (r) => identical(r, editedRecord),
        );
        if (editedIdx != -1) {
          for (var i = editedIdx + 1; i < seriesRecords.length; i++) {
            seriesRecords[i].date = _dateOnly(
              seriesRecords[i].date.add(Duration(days: daysDiff)),
            );
          }
        }
      }
    }

    // 3. Puppy šablóna - posuň všetky nasledujúce šablónové záznamy
    if (daysDiff != 0 && editedRecord.note == _puppyTemplateNote) {
      final templateRecords = dog.records
          .where((r) => r.note == _puppyTemplateNote)
          .toList()
        ..sort((a, b) => a.date.compareTo(b.date));

      final editedIdx = templateRecords.indexWhere(
        (r) => identical(r, editedRecord),
      );
      if (editedIdx != -1) {
        for (var i = editedIdx + 1; i < templateRecords.length; i++) {
          templateRecords[i].date = _dateOnly(
            templateRecords[i].date.add(Duration(days: daysDiff)),
          );
        }
      }
    }
  }

  DateTime _calculateRepeatDate(DateTime base, int value, RepeatUnit unit) {
    switch (unit) {
      case RepeatUnit.days:
        return base.add(Duration(days: value));
      case RepeatUnit.weeks:
        return base.add(Duration(days: value * 7));
      case RepeatUnit.months:
        return DateTime(base.year, base.month + value, base.day);
    }
  }

  void _updateLastVaccination(DogProfile dog, DateTime vaccinationDate) {
    if (dog.lastVaccinationDate == null ||
        vaccinationDate.isAfter(dog.lastVaccinationDate!)) {
      dog.lastVaccinationDate = vaccinationDate;
      _ensureDogTypeByAge(dog);
      _syncAnnualRevaccinationRecord(dog);
      _syncPreVaccinationDewormingRecords(dog);
      _syncReminderRecords(dog);
    }
  }

  void _recalculateLastVaccination(DogProfile dog) {
    _ensureDogTypeByAge(dog);
    // Vylucime 'Preočkovanie po roku' z vypoctu - je to auto-generovany zaznam
    final vaccinations = dog.records
        .where(
          (record) =>
              record.type == ProcedureType.vaccination &&
              record.title != _annualRevaccinationTitle,
        )
        .toList();
    if (vaccinations.isEmpty) {
      dog.lastVaccinationDate = null;
      dog.records.removeWhere(
        (record) => record.title == _annualRevaccinationTitle,
      );
      _syncPreVaccinationDewormingRecords(dog);
      _syncReminderRecords(dog);
      return;
    }
    vaccinations.sort((a, b) => a.date.compareTo(b.date));
    dog.lastVaccinationDate = vaccinations.last.date;
    _syncAnnualRevaccinationRecord(dog);
    _syncPreVaccinationDewormingRecords(dog);
    _syncReminderRecords(dog);
  }

  bool _shouldShowNote(String note) {
    final trimmed = note.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    final lower = trimmed.toLowerCase();
    return trimmed != _autoDewormingNote &&
        trimmed != _autoReminderNote &&
        trimmed != _puppyTemplateNote &&
        !lower.startsWith('automaticky');
  }

  Future<void> _deleteRecord(DogProfile dog, HealthRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Zmazať záznam?'),
        content: Text('Natrvalo sa odstráni: ${record.title}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Zrušiť'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Zmazať'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      dog.records.remove(record);
      _recalculateLastVaccination(dog);
    });
    _persist();
  }

  bool _ensureDogTypeByAge(DogProfile dog) {
    if (dog.type != DogType.puppy || dog.birthDate == null) {
      return false;
    }
    final oneYearDate = DateTime(
      dog.birthDate!.year + 1,
      dog.birthDate!.month,
      dog.birthDate!.day,
    );
    if (!_dateOnly(DateTime.now()).isBefore(_dateOnly(oneYearDate))) {
      dog.type = DogType.adult;
      return true;
    }
    return false;
  }

  void _syncDogSchedule(DogProfile dog) {
    _ensureDogTypeByAge(dog);
    _syncAnnualRevaccinationRecord(dog);
    _syncPreVaccinationDewormingRecords(dog);
    _syncReminderRecords(dog);
  }

  void _syncAnnualRevaccinationRecord(DogProfile dog) {
    if (dog.lastVaccinationDate == null) {
      dog.records.removeWhere(
        (record) => record.title == _annualRevaccinationTitle,
      );
      return;
    }
    final annualDate = _annualFrom(dog.lastVaccinationDate!);
    final existingIndex = dog.records.indexWhere(
      (record) => record.title == _annualRevaccinationTitle,
    );

    final annualRecord = HealthRecord(
      title: _annualRevaccinationTitle,
      type: ProcedureType.vaccination,
      date: annualDate,
      completed: false,
      note: '',
    );

    if (existingIndex == -1) {
      dog.records.add(annualRecord);
      return;
    }
    dog.records[existingIndex] = annualRecord;
  }

  void _syncPreVaccinationDewormingRecords(DogProfile dog) {
    dog.records.removeWhere((record) => record.note == _autoDewormingNote);
    if (dog.type == DogType.puppy) {
      return;
    }

    final vaccinationRecords = dog.records
        .where(
          (record) =>
              record.type == ProcedureType.vaccination && !record.completed,
        )
        .toList();

    for (final vaccination in vaccinationRecords) {
      dog.records.add(
        HealthRecord(
          title: 'Odčervenie (7 dní pred): ${vaccination.title}',
          type: ProcedureType.deworming,
          date: _dateOnly(
            vaccination.date.subtract(const Duration(days: 7)),
          ),
          note: _autoDewormingNote,
        ),
      );
    }
  }

  void _syncReminderRecords(DogProfile dog) {
    // Reminders only via native notifications now.
  }

  DateTime? _nextAnnualVaccinationDate(DogProfile dog) {
    if (dog.lastVaccinationDate == null) {
      return null;
    }
    return _annualFrom(dog.lastVaccinationDate!);
  }

  DateTime _annualFrom(DateTime date) {
    return _dateOnly(date).add(const Duration(days: 365));
  }

  void _persist() {
    for (final dog in _dogs) {
      _syncDogSchedule(dog);
    }
    _saveStateToAndroid();
    _scheduleNativeNotifications();
  }

  Future<void> _requestNativeNotificationPermission() async {
    try {
      await _storageChannel
          .invokeMethod<void>('requestNotificationPermission');
    } catch (_) {}
  }

  Future<void> _scheduleNativeNotifications() async {
    try {
      final now = DateTime.now();
      final reminders = <Map<String, dynamic>>[];
      for (final dog in _dogs) {
        for (final record in dog.records) {
          if (record.completed ||
              record.note == _autoReminderNote ||
              record.title.startsWith('Pripomienka')) {
            continue;
          }
          for (final daysBefore in const [7, 1]) {
            final remindAt = DateTime(
              record.date.year,
              record.date.month,
              record.date.day,
              9,
            ).subtract(Duration(days: daysBefore));
            if (remindAt.isBefore(now)) {
              continue;
            }
            final id = _stableReminderId(
              dog.id,
              record.title,
              record.date,
              daysBefore,
            );
            reminders.add({
              'id': id,
              'title': dog.name,
              'body':
                  '${record.title} je o ${daysBefore == 1 ? '1 deň' : '7 dní'} (${_formatDate(record.date)}).',
              'timestamp': remindAt.millisecondsSinceEpoch,
            });
          }
        }
      }
      await _storageChannel.invokeMethod<void>(
        'scheduleNotifications',
        reminders,
      );
    } catch (_) {}
  }

  int _stableReminderId(
    String dogId,
    String title,
    DateTime date,
    int daysBefore,
  ) {
    final source = '$dogId|$title|${date.toIso8601String()}|$daysBefore';
    var hash = 2166136261;
    for (final unit in source.codeUnits) {
      hash ^= unit;
      hash = (hash * 16777619) & 0x7fffffff;
    }
    return hash;
  }

  Future<void> _loadStateFromAndroid() async {
    try {
      final jsonState =
          await _storageChannel.invokeMethod<String>('loadState');
      if (jsonState == null || jsonState.isEmpty) {
        return;
      }
      final decoded = jsonDecode(jsonState) as Map<String, dynamic>;
      final dogsRaw = decoded['dogs'] as List<dynamic>? ?? [];
      _dogs
        ..clear()
        ..addAll(
          dogsRaw.map(
            (item) => DogProfile.fromMap(item as Map<String, dynamic>),
          ),
        );
      for (final dog in _dogs) {
        _syncDogSchedule(dog);
      }
      _selectedDogId = decoded['selectedDogId'] as String?;
      if (_dogs.isNotEmpty &&
          (_selectedDogId == null ||
              _dogs.every((d) => d.id != _selectedDogId))) {
        _selectedDogId = _dogs.first.id;
      }
    } catch (_) {}
  }

  Future<void> _saveStateToAndroid() async {
    try {
      final payload = <String, dynamic>{
        'selectedDogId': _selectedDogId,
        'dogs': _dogs.map((dog) => dog.toMap()).toList(),
      };
      await _storageChannel.invokeMethod<void>(
        'saveState',
        jsonEncode(payload),
      );
    } catch (_) {}
  }

  String _labelForType(ProcedureType type) {
    switch (type) {
      case ProcedureType.vaccination:
        return 'Očkovanie';
      case ProcedureType.deworming:
        return 'Odčervenie';
      case ProcedureType.medication:
        return 'Lieky (napr. Cytopoint)';
      case ProcedureType.checkup:
        return 'Veterinárna kontrola';
      case ProcedureType.other:
        return 'Iné';
    }
  }

  String _dogTypeLabel(DogType type) {
    switch (type) {
      case DogType.puppy:
        return 'šteniatko';
      case DogType.adult:
        return 'dospelý pes';
    }
  }

  IconData _dogTypeIcon(DogType type) {
    switch (type) {
      case DogType.puppy:
        return Icons.pets;
      case DogType.adult:
        return Icons.pets_outlined;
    }
  }

  IconData _iconForType(ProcedureType type) {
    switch (type) {
      case ProcedureType.vaccination:
        return Icons.vaccines;
      case ProcedureType.deworming:
        return Icons.medication_liquid;
      case ProcedureType.medication:
        return Icons.medication;
      case ProcedureType.checkup:
        return Icons.health_and_safety;
      case ProcedureType.other:
        return Icons.notes;
    }
  }

  DateTime _dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  int _ageInWeeks(DateTime birthDate) {
    final days = DateTime.now().difference(_dateOnly(birthDate)).inDays;
    if (days <= 0) {
      return 0;
    }
    return days ~/ 7;
  }

  String _formatAgeSk(DateTime birthDate) {
    final now = _dateOnly(DateTime.now());
    final birth = _dateOnly(birthDate);
    if (!now.isAfter(birth)) {
      return '0 týždňov';
    }

    final totalMonths = (now.year - birth.year) * 12 + now.month - birth.month - (now.day < birth.day ? 1 : 0);
    if (totalMonths < 3) {
      return _formatWeeksSk(_ageInWeeks(birthDate));
    }

    if (totalMonths < 12) {
      return _formatMonthsSk(totalMonths);
    }

    var years = now.year - birth.year;
    if (now.month < birth.month || (now.month == birth.month && now.day < birth.day)) {
      years--;
    }
    return _formatYearsSk(years);
  }

  String _formatWeeksSk(int weeks) {
    final mod100 = weeks % 100;
    final mod10 = weeks % 10;
    if (mod100 >= 11 && mod100 <= 14) {
      return '$weeks týždňov';
    }
    if (mod10 == 1) {
      return '$weeks týždeň';
    }
    if (mod10 >= 2 && mod10 <= 4) {
      return '$weeks týždne';
    }
    return '$weeks týždňov';
  }

  String _formatMonthsSk(int months) {
    final mod100 = months % 100;
    final mod10 = months % 10;
    if (mod100 >= 11 && mod100 <= 14) {
      return '$months mesiacov';
    }
    if (mod10 == 1) {
      return '$months mesiac';
    }
    if (mod10 >= 2 && mod10 <= 4) {
      return '$months mesiace';
    }
    return '$months mesiacov';
  }

  String _formatYearsSk(int years) {
    final mod100 = years % 100;
    final mod10 = years % 10;
    if (mod100 >= 11 && mod100 <= 14) {
      return '$years rokov';
    }
    if (mod10 == 1) {
      return '$years rok';
    }
    if (mod10 >= 2 && mod10 <= 4) {
      return '$years roky';
    }
    return '$years rokov';
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();
    return '$day.$month.$year';
  }
}

class AddDogPage extends StatefulWidget {
  const AddDogPage({super.key, this.fixedType});

  final DogType? fixedType;

  @override
  State<AddDogPage> createState() => _AddDogPageState();
}

class _AddDogPageState extends State<AddDogPage> {
  static const MethodChannel _storageChannel = MethodChannel(
    'pet_health/storage',
  );
  late DogType _selectedType;
  late DateTime _selectedDate;
  late DateTime _adultDewormingDate;
  bool _useAdultDewormingDate = false;
  DateTime? _adultBirthDate;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _photoUrlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedType = widget.fixedType ?? DogType.adult;
    _selectedDate = _selectedType == DogType.puppy
        ? DateTime(
            now.year,
            now.month,
            now.day,
          ).subtract(const Duration(days: 56))
        : DateTime(
            now.year,
            now.month,
            now.day,
          ).subtract(const Duration(days: 180));
    _adultDewormingDate = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 90));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _weightController.dispose();
    _photoUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return Scaffold(
      appBar: AppBar(title: const Text('Pridať psa')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + bottomInset),
        children: [
          DropdownButtonFormField<DogType>(
            initialValue: _selectedType,
            decoration: const InputDecoration(labelText: 'Typ psa'),
            items: const [
              DropdownMenuItem(value: DogType.puppy, child: Text('šteniatko')),
              DropdownMenuItem(
                value: DogType.adult,
                child: Text('dospelý pes'),
              ),
            ],
            onChanged: widget.fixedType != null
                ? null
                : (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _selectedType = value;
                      _selectedDate = _selectedType == DogType.puppy
                          ? DateTime(
                              now.year,
                              now.month,
                              now.day,
                            ).subtract(const Duration(days: 56))
                          : DateTime(
                              now.year,
                              now.month,
                              now.day,
                            ).subtract(const Duration(days: 180));
                      if (_selectedType == DogType.puppy) {
                        _useAdultDewormingDate = false;
                      }
                    });
                  },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Meno psa (voliteľné)',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _weightController,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Váha (kg, voliteľné)',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _photoUrlController,
            decoration: const InputDecoration(
              labelText: 'Cesta/URL fotky (voliteľné)',
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () async {
                final picked = await _pickPhotoFromPhone();
                if (picked == null || !mounted) {
                  return;
                }
                setState(() {
                  _photoUrlController.text = picked;
                });
              },
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Vybrať fotku z telefónu'),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            _selectedType == DogType.puppy
                ? 'Dátum narodenia'
                : 'Dátum posledného očkovania',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          CalendarDatePicker(
            initialDate: _selectedDate,
            firstDate: DateTime(2010),
            lastDate: DateTime(now.year, now.month, now.day),
            onDateChanged: (value) {
              setState(() {
                _selectedDate = DateTime(value.year, value.month, value.day);
              });
            },
          ),
          if (_selectedType == DogType.adult) ...[
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _useAdultDewormingDate,
              title: const Text('Poznám dátum posledného odčervenia'),
              subtitle: const Text(
                'Ak zadáš dátum, nastaví sa odčervenie každé 3 mesiace.',
              ),
              onChanged: (value) {
                setState(() {
                  _useAdultDewormingDate = value;
                });
              },
            ),
            if (_useAdultDewormingDate)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Posledné odčervenie'),
                subtitle: Text(_formatDate(_adultDewormingDate)),
                trailing: const Icon(Icons.calendar_today_outlined, size: 18),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _adultDewormingDate,
                    firstDate: DateTime(2010),
                    lastDate: DateTime(now.year, now.month, now.day),
                  );
                  if (picked == null || !context.mounted) return;
                  setState(() {
                    _adultDewormingDate = DateTime(
                      picked.year,
                      picked.month,
                      picked.day,
                    );
                  });
                },
              ),
          ],
          if (_selectedType == DogType.adult) ...[
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _adultBirthDate != null,
              title: const Text('Poznám dátum narodenia'),
              subtitle: const Text('Voliteľné — zobrazí sa vek psa.'),
              onChanged: (value) async {
                if (value) {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime(
                      now.year - 2,
                      now.month,
                      now.day,
                    ),
                    firstDate: DateTime(2010),
                    lastDate: DateTime(now.year, now.month, now.day),
                  );
                  if (picked == null || !mounted) return;
                  setState(() {
                    _adultBirthDate = DateTime(
                      picked.year,
                      picked.month,
                      picked.day,
                    );
                  });
                } else {
                  setState(() {
                    _adultBirthDate = null;
                  });
                }
              },
            ),
            if (_adultBirthDate != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Dátum narodenia'),
                subtitle: Text(_formatDate(_adultBirthDate!)),
                trailing: const Icon(Icons.cake_outlined, size: 18),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _adultBirthDate!,
                    firstDate: DateTime(2010),
                    lastDate: DateTime(now.year, now.month, now.day),
                  );
                  if (picked == null || !mounted) return;
                  setState(() {
                    _adultBirthDate = DateTime(
                      picked.year,
                      picked.month,
                      picked.day,
                    );
                  });
                },
              ),
          ],
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () {
              final parsedWeight = _doubleFromDynamic(
                _weightController.text.trim().replaceAll(',', '.'),
              );
              final trimmedPhoto = _photoUrlController.text.trim();
              Navigator.of(context).pop(
                _DogDraftWithType(
                  type: _selectedType,
                  name: _nameController.text.trim(),
                  date: _selectedDate,
                  weightKg: parsedWeight,
                  photoUrl: trimmedPhoto.isEmpty ? null : trimmedPhoto,
                  lastDewormingDate:
                      _selectedType == DogType.adult && _useAdultDewormingDate
                          ? _adultDewormingDate
                          : null,
                  birthDate: _selectedType == DogType.adult
                      ? _adultBirthDate
                      : null,
                ),
              );
            },
            child: const Text('Uložiť'),
          ),
        ],
      ),
    );
  }

  Future<String?> _pickPhotoFromPhone() async {
    try {
      return await _storageChannel.invokeMethod<String>('pickDogPhoto');
    } catch (_) {
      return null;
    }
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();
    return '$day.$month.$year';
  }
}

class AddRecordPage extends StatefulWidget {
  const AddRecordPage({super.key});

  @override
  State<AddRecordPage> createState() => _AddRecordPageState();
}

class _AddRecordPageState extends State<AddRecordPage> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  final TextEditingController _repeatValueController = TextEditingController();
  ProcedureType _selectedType = ProcedureType.checkup;
  bool _repeatEnabled = false;
  RepeatUnit _repeatUnit = RepeatUnit.days;
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    _repeatValueController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return Scaffold(
      appBar: AppBar(title: const Text('Nový záznam')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(labelText: 'Názov úkonu'),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<ProcedureType>(
            initialValue: _selectedType,
            decoration: const InputDecoration(labelText: 'Typ'),
            items: ProcedureType.values
                .map(
                  (type) => DropdownMenuItem(
                    value: type,
                    child: Text(_labelForTypeInPage(type)),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) {
                return;
              }
              setState(() {
                _selectedType = value;
              });
            },
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _noteController,
            decoration: const InputDecoration(
              labelText: 'Poznámka (voliteľná)',
            ),
          ),
          const SizedBox(height: 10),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Opakovať úkon'),
            subtitle: const Text('Používateľ zadá počet a jednotku.'),
            value: _repeatEnabled,
            onChanged: (value) {
              setState(() {
                _repeatEnabled = value;
              });
            },
          ),
          if (_repeatEnabled) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _repeatValueController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Počet',
                      hintText: 'napr. 3',
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: DropdownButtonFormField<RepeatUnit>(
                    initialValue: _repeatUnit,
                    decoration: const InputDecoration(labelText: 'Jednotka'),
                    items: const [
                      DropdownMenuItem(
                        value: RepeatUnit.days,
                        child: Text('dni'),
                      ),
                      DropdownMenuItem(
                        value: RepeatUnit.weeks,
                        child: Text('týždne'),
                      ),
                      DropdownMenuItem(
                        value: RepeatUnit.months,
                        child: Text('mesiace'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() {
                        _repeatUnit = value;
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Príklad: 6 týždňov alebo 12 mesiacov.',
              style: TextStyle(fontSize: 12),
            ),
          ],
          const SizedBox(height: 10),
          const Text(
            'Pri očkovaní sa preočkovanie vytvorí podľa zadaného intervalu.',
          ),
          const SizedBox(height: 14),
          Text('Dátum úkonu', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          CalendarDatePicker(
            initialDate: _selectedDate,
            firstDate: DateTime(2020),
            lastDate: today.add(const Duration(days: 3650)),
            onDateChanged: (value) {
              setState(() {
                _selectedDate = DateTime(value.year, value.month, value.day);
              });
            },
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () {
              final title = _titleController.text.trim();
              if (title.isEmpty) {
                return;
              }
              int? repeatValue;
              RepeatUnit? repeatUnit;
              if (_repeatEnabled) {
                repeatValue =
                    int.tryParse(_repeatValueController.text.trim());
                if (repeatValue == null || repeatValue <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Zadaj platný počet (aspoň 1).'),
                    ),
                  );
                  return;
                }
                repeatUnit = _repeatUnit;
              }
              Navigator.of(context).pop(
                _RecordDraft(
                  title: title,
                  type: _selectedType,
                  date: _selectedDate,
                  note: _noteController.text.trim(),
                  repeatValue: repeatValue,
                  repeatUnit: repeatUnit,
                ),
              );
            },
            child: const Text('Uložiť'),
          ),
        ],
      ),
    );
  }

  String _labelForTypeInPage(ProcedureType type) {
    switch (type) {
      case ProcedureType.vaccination:
        return 'Očkovanie';
      case ProcedureType.deworming:
        return 'Odčervenie';
      case ProcedureType.medication:
        return 'Lieky (napr. Cytopoint)';
      case ProcedureType.checkup:
        return 'Veterinárna kontrola';
      case ProcedureType.other:
        return 'Iné';
    }
  }
}
