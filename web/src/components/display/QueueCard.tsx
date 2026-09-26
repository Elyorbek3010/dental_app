import React from 'react';
import { AlertCircle, DoorOpen, UserCheck, Users } from 'lucide-react';
import type { PublicDisplayQueue } from '../../types/display';

interface QueueCardProps {
  queue: PublicDisplayQueue;
}

export const QueueCard: React.FC<QueueCardProps> = ({ queue }) => {
  const { doctor, specialization, is_paused, called_ticket, waiting_tickets } = queue;

  return (
    <article className="flex flex-col bg-slate-900/90 rounded-2xl border border-slate-800 shadow-2xl overflow-hidden transition-all duration-300">
      {/* Paused Banner */}
      {is_paused && (
        <div className="bg-amber-500/20 border-b border-amber-500/30 px-4 py-2 flex items-center justify-center gap-2 text-amber-300 font-semibold text-sm tracking-wide uppercase">
          <AlertCircle className="w-4 h-4 shrink-0" />
          Queue paused
        </div>
      )}

      {/* Doctor & Room Header */}
      <header className="p-5 border-b border-slate-800/80 bg-slate-800/40 flex items-start justify-between gap-4">
        <div>
          <h2 className="text-xl md:text-2xl font-bold text-white tracking-tight m-0">
            {doctor.full_name}
          </h2>
          <p className="text-sm md:text-base font-medium text-cyan-400 m-0 mt-0.5">
            {specialization.name}
          </p>
        </div>

        {doctor.room_number && (
          <div className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-blue-500/20 border border-blue-400/30 text-blue-300 font-semibold text-sm tracking-wide shrink-0">
            <DoorOpen className="w-4 h-4" />
            <span>{doctor.room_number}</span>
          </div>
        )}
      </header>

      {/* Body: NOW CALLING Section */}
      <section className="p-6 flex-1 flex flex-col items-center justify-center text-center bg-gradient-to-b from-slate-900/40 to-slate-950/60 border-b border-slate-800/80">
        <span className="text-xs md:text-sm font-extrabold uppercase tracking-widest text-slate-400 flex items-center gap-2 mb-2">
          <UserCheck className="w-4 h-4 text-emerald-400" />
          NOW CALLING
        </span>

        {called_ticket ? (
          <div className="flex flex-col items-center justify-center my-2">
            <div className="text-6xl md:text-7xl lg:text-8xl font-black font-mono tracking-tighter text-emerald-400 drop-shadow-[0_0_25px_rgba(52,211,153,0.3)] animate-pulse">
              №{called_ticket.ticket_number}
            </div>
            {doctor.room_number && (
              <div className="mt-3 inline-flex items-center gap-2 px-4 py-1.5 rounded-full bg-emerald-500/10 border border-emerald-500/30 text-emerald-300 font-bold text-base md:text-lg tracking-wider uppercase">
                <DoorOpen className="w-5 h-5 text-emerald-400" />
                {doctor.room_number.toUpperCase().startsWith('ROOM')
                  ? doctor.room_number.toUpperCase()
                  : `ROOM ${doctor.room_number.toUpperCase()}`}
              </div>
            )}
          </div>
        ) : (
          <div className="py-8 text-slate-400 text-lg md:text-xl font-medium italic flex items-center justify-center gap-2">
            Waiting for next patient
          </div>
        )}
      </section>

      {/* Footer: WAITING Tickets Section */}
      <footer className="p-5 bg-slate-950/80">
        <div className="flex items-center justify-between gap-2 mb-3">
          <span className="text-xs font-bold uppercase tracking-wider text-slate-400 flex items-center gap-1.5">
            <Users className="w-4 h-4 text-cyan-400" />
            WAITING
          </span>
          <span className="text-xs font-semibold px-2 py-0.5 rounded-full bg-slate-800 text-slate-300 border border-slate-700">
            {waiting_tickets.length} {waiting_tickets.length === 1 ? 'patient' : 'patients'}
          </span>
        </div>

        {waiting_tickets.length > 0 ? (
          <div className="flex flex-wrap gap-2.5 max-h-36 overflow-y-auto scrollbar-thin">
            {waiting_tickets.map((t) => (
              <span
                key={t.ticket_number}
                className="px-3.5 py-1.5 rounded-xl bg-slate-800/90 hover:bg-slate-700/90 text-white font-mono font-bold text-base md:text-lg border border-slate-700 shadow-sm transition-colors"
              >
                №{t.ticket_number}
              </span>
            ))}
          </div>
        ) : (
          <div className="text-sm md:text-base text-slate-400 font-medium italic py-2 text-center">
            No patients waiting
          </div>
        )}
      </footer>
    </article>
  );
};
