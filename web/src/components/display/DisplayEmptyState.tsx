import React from 'react';
import { CalendarX } from 'lucide-react';

export const DisplayEmptyState: React.FC = () => {
  return (
    <div className="flex-1 flex flex-col items-center justify-center p-10 text-center bg-[#071422] animate-dental-in">
      <div className="w-24 h-24 rounded-3xl bg-[#12243A] border border-[#253F5B] flex items-center justify-center mb-6 shadow-2xl">
        <CalendarX className="w-11 h-11 text-[#2DD4BF]" />
      </div>
      <h2 className="text-2xl md:text-3xl font-extrabold text-[#F1F5F9] tracking-tight mb-2">
        No active queues today
      </h2>
      <p className="text-[#A5B4C7] text-sm md:text-base max-w-md font-medium">
        There are currently no scheduled or active doctor queues for this clinic today.
      </p>
    </div>
  );
};
