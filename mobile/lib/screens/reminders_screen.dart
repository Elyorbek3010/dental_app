import 'package:flutter/material.dart';

import '../models/reminder.dart';
import '../services/reminder_service.dart';

/// Screen allowing the patient to view, add, edit, and delete their personal reminders.
class RemindersScreen extends StatefulWidget {
  const RemindersScreen({
    super.key,
    this.reminderService,
  });

  final ReminderService? reminderService;

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  late final ReminderService _reminderService;
  List<Reminder> _reminders = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _reminderService = widget.reminderService ?? ReminderService.instance;
    _loadReminders();
  }

  Future<void> _loadReminders({bool showLoading = false}) async {
    if (showLoading && mounted && !_isLoading) {
      setState(() => _isLoading = true);
    }
    final reminders = await _reminderService.getReminders();
    if (mounted) {
      setState(() {
        _reminders = reminders;
        _isLoading = false;
      });
    }
  }

  String _formatDate(DateTime dt) {
    final y = dt.year;
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$h:$min';
  }

  Future<void> _showReminderForm({Reminder? existing}) async {
    final isEditing = existing != null;
    DateTime initialDate;
    TimeOfDay initialTime;

    if (isEditing) {
      initialDate = existing.scheduledAt;
      initialTime = TimeOfDay.fromDateTime(existing.scheduledAt);
    } else {
      // Default to 1 hour in the future
      final futureDefault = DateTime.now().add(const Duration(hours: 1));
      initialDate = DateTime(futureDefault.year, futureDefault.month, futureDefault.day);
      initialTime = TimeOfDay(hour: futureDefault.hour, minute: futureDefault.minute);
    }

    DateTime selectedDate = initialDate;
    TimeOfDay selectedTime = initialTime;
    final noteController = TextEditingController(text: existing?.note ?? '');
    String? errorMessage;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isEditing ? 'Eslatmani tahrirlash' : 'Yangi eslatma qo‘shish',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(sheetContext),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Date Picker Tile
                    ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      leading: const Icon(Icons.calendar_today, color: Colors.blueAccent),
                      title: const Text('Sana (Date)'),
                      subtitle: Text(
                        _formatDate(selectedDate),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () async {
                        final now = DateTime.now();
                        final picked = await showDatePicker(
                          context: sheetContext,
                          initialDate: selectedDate.isBefore(now) ? now : selectedDate,
                          firstDate: DateTime(now.year, now.month, now.day),
                          lastDate: DateTime(now.year + 5),
                        );
                        if (picked != null) {
                          setModalState(() {
                            selectedDate = picked;
                            errorMessage = null;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),

                    // Time Picker Tile
                    ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      leading: const Icon(Icons.access_time, color: Colors.blueAccent),
                      title: const Text('Vaqt (Time)'),
                      subtitle: Text(
                        '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: sheetContext,
                          initialTime: selectedTime,
                        );
                        if (picked != null) {
                          setModalState(() {
                            selectedTime = picked;
                            errorMessage = null;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),

                    // Note Input
                    TextField(
                      controller: noteController,
                      maxLength: 100,
                      decoration: InputDecoration(
                        labelText: 'Qisqa eslatma (Note - ixtiyoriy)',
                        hintText: 'Masalan: Tish tekshiruvi (Dental check-up)',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        prefixIcon: const Icon(Icons.note_alt_outlined),
                      ),
                    ),

                    if (errorMessage != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        errorMessage!,
                        style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                      ),
                    ],

                    const SizedBox(height: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () async {
                        final combinedDateTime = DateTime(
                          selectedDate.year,
                          selectedDate.month,
                          selectedDate.day,
                          selectedTime.hour,
                          selectedTime.minute,
                        );

                        if (combinedDateTime.isBefore(DateTime.now())) {
                          setModalState(() {
                            errorMessage =
                                'Eslatma vaqti kelajakda bo‘lishi kerak (Must be in the future).';
                          });
                          return;
                        }

                        final messenger = ScaffoldMessenger.of(this.context);
                        Navigator.pop(sheetContext);

                        try {
                          if (isEditing) {
                            await _reminderService.updateReminder(
                              id: existing.id,
                              scheduledAt: combinedDateTime,
                              note: noteController.text,
                            );
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Eslatma muvaffaqiyatli yangilandi.'),
                              ),
                            );
                          } else {
                            await _reminderService.createReminder(
                              scheduledAt: combinedDateTime,
                              note: noteController.text,
                            );
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Yangi eslatma saqlandi va rejalashtirildi.'),
                              ),
                            );
                          }
                          await _loadReminders();
                        } catch (e) {
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text('Xatolik yuz berdi: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      },
                      child: Text(
                        isEditing ? 'Yangilash (Update)' : 'Saqlash (Save)',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _deleteReminder(Reminder reminder) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Eslatmani o‘chirish'),
          content: Text(
            'Haqiqatan ham ushbu eslatmani o‘chirmoqchimisiz?\n\n'
            'Sana: ${_formatDate(reminder.scheduledAt)} ${_formatTime(reminder.scheduledAt)}\n'
            'Matn: ${reminder.note ?? ReminderService.defaultNotificationBody}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Bekor qilish'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('O‘chirish'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _reminderService.deleteReminder(reminder.id);
      messenger.showSnackBar(
        const SnackBar(content: Text('Eslatma o‘chirildi.')),
      );
      await _loadReminders();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Eslatmalarim'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_alarm),
            tooltip: 'Yangi eslatma',
            onPressed: () => _showReminderForm(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _reminders.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadReminders,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: _reminders.length,
                    itemBuilder: (context, index) {
                      final item = _reminders[index];
                      return _buildReminderCard(item);
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showReminderForm(),
        icon: const Icon(Icons.add),
        label: const Text('Eslatma qo‘shish'),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.notifications_active_outlined,
              size: 80,
              color: Colors.blueAccent.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 16),
            Text(
              'Hozircha eslatmalar yo‘q',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Stomatolog ko‘rigi yoki tashrifingizni unutmang.\n'
              'O‘zingiz uchun qulay sana va vaqtga eslatma o‘rnating.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, height: 1.4),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _showReminderForm(),
              icon: const Icon(Icons.add),
              label: const Text('Eslatma qo‘shish'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReminderCard(Reminder reminder) {
    final isPast = reminder.isPast;
    final dateStr = _formatDate(reminder.scheduledAt);
    final timeStr = _formatTime(reminder.scheduledAt);
    final noteStr = reminder.note ?? ReminderService.defaultNotificationBody;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.alarm,
                      color: isPast ? Colors.grey : Colors.blueAccent,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$dateStr • $timeStr',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: isPast ? Colors.grey : null,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isPast ? Colors.grey.shade200 : Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isPast ? 'O‘tgan' : 'Kutilmoqda',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isPast ? Colors.grey.shade700 : Colors.blue.shade700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              noteStr,
              style: TextStyle(
                fontSize: 14,
                color: isPast ? Colors.grey.shade600 : Colors.black87,
              ),
            ),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _showReminderForm(existing: reminder),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Tahrirlash'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () => _deleteReminder(reminder),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('O‘chirish'),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
