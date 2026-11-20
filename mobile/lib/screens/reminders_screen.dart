import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/reminder.dart';
import '../services/reminder_service.dart';
import '../theme/app_theme.dart';
import '../widgets/empty_state_card.dart';
import '../widgets/loading_skeleton.dart';

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
    final l10n = context.l10n;
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

    final colors = context.dentalColors;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
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
                          isEditing
                              ? l10n.editReminderModalTitle
                              : l10n.addReminderModalTitle,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: colors.textPrimary,
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close, color: colors.textSecondary),
                          onPressed: () => Navigator.pop(sheetContext),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Date Picker Tile
                    ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(color: colors.border),
                      ),
                      tileColor: colors.surfaceMuted,
                      leading: Icon(Icons.calendar_today_rounded, color: colors.teal),
                      title: Text(
                        l10n.reminderDateLabel,
                        style: TextStyle(color: colors.textSecondary, fontSize: 13),
                      ),
                      subtitle: Text(
                        _formatDate(selectedDate),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: colors.textPrimary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      trailing: Icon(Icons.arrow_forward_ios_rounded, size: 16, color: colors.textMuted),
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
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(color: colors.border),
                      ),
                      tileColor: colors.surfaceMuted,
                      leading: Icon(Icons.access_time_rounded, color: colors.blue),
                      title: Text(
                        l10n.reminderTimeLabel,
                        style: TextStyle(color: colors.textSecondary, fontSize: 13),
                      ),
                      subtitle: Text(
                        '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: colors.textPrimary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      trailing: Icon(Icons.arrow_forward_ios_rounded, size: 16, color: colors.textMuted),
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
                        labelText: l10n.reminderNoteLabel,
                        hintText: l10n.reminderNoteHint,
                        prefixIcon: const Icon(Icons.note_alt_outlined),
                      ),
                    ),

                    if (errorMessage != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        errorMessage!,
                        style: TextStyle(color: colors.error, fontWeight: FontWeight.w700),
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
                            errorMessage = l10n.reminderFutureError;
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
                              defaultBody: l10n.defaultReminderNotificationBody,
                            );
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(l10n.reminderUpdatedSuccess),
                              ),
                            );
                          } else {
                            await _reminderService.createReminder(
                              scheduledAt: combinedDateTime,
                              note: noteController.text,
                              defaultBody: l10n.defaultReminderNotificationBody,
                            );
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(l10n.reminderCreatedSuccess),
                              ),
                            );
                          }
                          await _loadReminders();
                        } catch (e) {
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(e.toString()),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      },
                      child: Text(
                        isEditing ? l10n.updateButton : l10n.saveButton,
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
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.deleteReminderDialogTitle),
          content: Text(
            '${l10n.deleteReminderDialogContent}\n\n'
            '${l10n.reminderDateLabel}: ${_formatDate(reminder.scheduledAt)} ${_formatTime(reminder.scheduledAt)}\n'
            '${reminder.note ?? l10n.defaultReminderNotificationBody}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(l10n.cancelButton),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text(l10n.deleteButton),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _reminderService.deleteReminder(reminder.id);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.reminderDeletedSuccess)),
      );
      await _loadReminders();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.dentalColors;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.remindersTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_alarm_rounded),
            tooltip: l10n.newReminderTooltip,
            onPressed: () => _showReminderForm(),
          ),
        ],
      ),
      body: _isLoading
          ? const LoadingSkeleton(itemCount: 3)
          : _reminders.isEmpty
              ? _buildEmptyState(l10n)
              : RefreshIndicator(
                  onRefresh: _loadReminders,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    itemCount: _reminders.length,
                    itemBuilder: (context, index) {
                      final item = _reminders[index];
                      return _buildReminderCard(item, l10n, colors);
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: colors.teal,
        foregroundColor: Colors.white,
        onPressed: () => _showReminderForm(),
        icon: const Icon(Icons.add_rounded),
        label: Text(l10n.addReminderButton),
      ),
    );
  }

  Widget _buildEmptyState(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: EmptyStateCard(
          icon: Icons.notifications_active_outlined,
          title: l10n.noRemindersTitle,
          description: l10n.noRemindersDesc,
          buttonText: l10n.addReminderButton,
          onButtonPressed: () => _showReminderForm(),
        ),
      ),
    );
  }

  Widget _buildReminderCard(
    Reminder reminder,
    AppLocalizations l10n,
    DentalThemeTokens colors,
  ) {
    final isPast = reminder.isPast;
    final dateStr = _formatDate(reminder.scheduledAt);
    final timeStr = _formatTime(reminder.scheduledAt);
    final noteStr = reminder.note ?? l10n.defaultReminderNotificationBody;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isPast ? colors.surfaceMuted : colors.blueSoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.alarm_rounded,
                      color: isPast ? colors.textMuted : colors.blue,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '$dateStr • $timeStr',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: isPast ? colors.textSecondary : colors.textPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isPast ? colors.surfaceMuted : colors.tealSoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  isPast ? l10n.reminderPastBadge : l10n.reminderWaitingBadge,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: isPast ? colors.textSecondary : colors.teal,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            noteStr,
            style: TextStyle(
              fontSize: 14,
              height: 1.4,
              color: isPast ? colors.textSecondary : colors.textPrimary,
            ),
          ),
          Divider(height: 22, color: colors.border),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () => _showReminderForm(existing: reminder),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text(l10n.editButton),
                style: TextButton.styleFrom(foregroundColor: colors.teal),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () => _deleteReminder(reminder),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: Text(l10n.deleteButton),
                style: TextButton.styleFrom(foregroundColor: colors.error),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
