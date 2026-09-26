import React from 'react';
import { Loader2 } from 'lucide-react';

export const DisplayLoadingState: React.FC = () => {
  return (
    <div className="flex-1 flex flex-col items-center justify-center p-8 text-center bg-slate-950">
      <div className="relative mb-6">
        <div className="w-16 h-16 rounded-full border-4 border-slate-800 border-t-cyan-400 animate-spin" />
        <Loader2 className="w-8 h-8 text-cyan-400 absolute inset-0 m-auto animate-pulse" />
      </div>
      <h2 className="text-2xl md:text-3xl font-bold text-white tracking-tight mb-2">
        Loading queue...
      </h2>
      <p className="text-slate-400 text-sm md:text-base font-medium">
        Connecting to queue system
      </p>
    </div>
  );
};
