import React from 'react';
import { AlertCircle, DoorOpen, UserCheck, Users } from 'lucide-react';
import { useSmartCallCountdown } from '../../hooks/useSmartCallCountdown';
import type { PublicDisplayQueue } from '../../types/display';
import { CountdownRing } from '../common/CountdownRing';

interface QueueCardProps {
  queue: PublicDisplayQueue;
  serverTime?: string | null;
  fetchedAtMs?: number | null;
}

export const QueueCard: React.FC<QueueCardProps> = ({
  queue,
  serverTime,
  fetchedAtMs,
}) => {
  const { doctor, specialization, is_paused, called_ticket, waiting_tickets } = queue;
  const remainingSeconds = useSmartCallCountdown({
    callDeadlineAt: called_ticket?.call_deadline_at,
    pausedRemainingSeconds: called_ticket?.paused_remaining_seconds,
    serverTime,
    fetchedAtMs,
    isPaused: is_paused,
  });

  const isCalling = Boolean(called_ticket);
  const isUrgent = remainingSeconds !== null && remainingSeconds <= 15 && !is_paused;

  return (
    <article
      className={`flex flex-col rounded-3xl border shadow-2xl overflow-hidden transition-all duration-300 ${
        isCalling && !is_paused
          ? 'bg-[#0B1728] border-[#2DD4BF]/55 animate-call-glow'
          : 'bg-[#0B1728] border-[#1E354E]'
      }`}
    >
      {/* Paused Banner */}
      {is_paused && (
        <div className="bg-amber-500/20 border-b border-amber-400/35 px-4 py-2 flex items-center justify-center gap-2 text-amber-300 font-bold text-xs md:text-sm tracking-wider uppercase">
          <AlertCircle className="w-4 h-4 shrink-0" />
          Queue paused
        </div>
      )}

      {/* Doctor & Room Header */}
      <header className="px-6 py-5 border-b border-[#1E354E] bg-[#12243A] flex items-start justify-between gap-4">
        <div className="min-w-0">
          <h2 className="text-xl md:text-2xl font-extrabold text-[#F1F5F9] tracking-tight m-0 truncate">
            {doctor.full_name}
          </h2>
          <p className="text-sm md:text-base font-semibold text-[#2DD4BF] m-0 mt-0.5 truncate">
            {specialization.name}
          </p>
        </div>

        {doctor.room_number && (
          <div className="flex items-center gap-1.5 px-3.5 py-1.5 rounded-xl bg-[#38BDF8]/15 border border-[#38BDF8]/35 text-[#38BDF8] font-bold text-sm tracking-wide shrink-0 tabular-nums">
            <DoorOpen className="w-4 h-4" />
            <span>{doctor.room_number}</span>
          </div>
        )}
      </header>

      {/* Body: NOW CALLING Section */}
      <section className="px-6 py-7 flex-1 flex flex-col items-center justify-center text-center bg-gradient-to-b from-[#0E1E32] to-[#071422] border-b border-[#1E354E]">
        <span className="inline-flex items-center gap-2 rounded-full bg-[#12243A] border border-[#253F5B] px-3.5 py-1 text-xs md:text-sm font-extrabold uppercase tracking-widest text-[#A5B4C7] mb-4">
          <UserCheck className="w-4 h-4 text-[#2DD4BF]" />
          NOW CALLING
        </span>

        {called_ticket ? (
          <div
            key={called_ticket.ticket_number}
            className="flex flex-col items-center justify-center gap-4 animate-dental-in"
          >
            <div className="flex items-center justify-center gap-5 flex-wrap">
              <div
                className={`text-6xl md:text-7xl lg:text-8xl font-black font-mono tracking-tight tabular-nums ${
                  isUrgent
                    ? 'text-amber-300 drop-shadow-[0_0_24px_rgba(245,158,11,0.35)]'
                    : 'text-[#2DD4BF] drop-shadow-[0_0_28px_rgba(45,212,191,0.35)]'
                }`}
              >
                №{called_ticket.ticket_number}
              </div>

              {remainingSeconds !== null && (
                <CountdownRing
                  remainingSeconds={remainingSeconds}
                  isPaused={is_paused}
                  size="lg"
                  forceDark
                  label="Remaining"
                  pausedLabel="Paused"
                />
              )}
            </div>

            {doctor.room_number && (
              <div className="inline-flex items-center gap-2 px-4 py-1.5 rounded-full bg-[#0D9488]/15 border border-[#2DD4BF]/35 text-[#2DD4BF] font-extrabold text-sm md:text-base tracking-wider uppercase tabular-nums">
                <DoorOpen className="w-4 h-4 text-[#2DD4BF]" />
                {doctor.room_number.toUpperCase().startsWith('ROOM')
                  ? doctor.room_number.toUpperCase()
                  : `ROOM ${doctor.room_number.toUpperCase()}`}
              </div>
            )}
          </div>
        ) : (
          <div className="py-8 text-[#A5B4C7] text-lg md:text-xl font-medium italic flex items-center justify-center gap-2">
            Waiting for next patient
          </div>
        )}
      </section>

      {/* Footer: WAITING Tickets Section */}
      <footer className="px-6 py-4 bg-[#091627]">
        <div className="flex items-center justify-between gap-2 mb-3">
          <span className="text-xs font-extrabold uppercase tracking-wider text-[#A5B4C7] flex items-center gap-1.5">
            <Users className="w-4 h-4 text-[#38BDF8]" />
            WAITING
          </span>
          <span className="text-xs font-bold px-2.5 py-0.5 rounded-full bg-[#12243A] text-[#F1F5F9] border border-[#253F5B] tabular-nums">
            {waiting_tickets.length} {waiting_tickets.length === 1 ? 'patient' : 'patients'}
          </span>
        </div>

        {waiting_tickets.length > 0 ? (
          <div className="flex flex-wrap gap-2 max-h-36 overflow-y-auto">
            {waiting_tickets.map((t, index) => (
              <span
                key={t.ticket_number}
                className={`px-3.5 py-1.5 rounded-xl font-mono font-bold text-base md:text-lg border tabular-nums ${
                  index === 0
                    ? 'bg-[#38BDF8]/15 border-[#38BDF8]/45 text-[#38BDF8]'
                    : 'bg-[#12243A] border-[#253F5B] text-[#F1F5F9]'
                }`}
              >
                №{t.ticket_number}
              </span>
            ))}
          </div>
        ) : (
          <div className="text-sm md:text-base text-[#A5B4C7]/75 font-medium italic py-1.5 text-center">
            No patients waiting
          </div>
        )}
      </footer>
    </article>
  );
};
