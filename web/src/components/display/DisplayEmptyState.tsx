import React from 'react';
import { CalendarX } from 'lucide-react';

export const DisplayEmptyState: React.FC = () => {
  return (
    <div className="flex-1 flex flex-col items-center justify-center p-8 text-center bg-slate-950">
      <div className="w-20 h-20 rounded-2xl bg-cyan-500/10 border border-cyan-500/20 flex items-center justify-center mb-6 shadow-xl shadow-cyan-950/30">
        <CalendarX className="w-10 h-10 text-cyan-400" />
      </div>
      <h2 className="text-2xl md:text-3xl font-bold text-white tracking-tight mb-2">
        No active queues today
      </h2>
      <p className="text-slate-400 text-sm md:text-base max-w-md font-medium">
        There are currently no scheduled or active doctor queues for this clinic today.
      </p>
    </div>
  );
};
