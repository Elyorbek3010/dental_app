import React, { useEffect, useState } from 'react';
import { Activity, Clock } from 'lucide-react';

interface DisplayHeaderProps {
  clinicName: string;
}

export const DisplayHeader: React.FC<DisplayHeaderProps> = ({ clinicName }) => {
  const [currentTime, setCurrentTime] = useState<Date>(new Date());

  useEffect(() => {
    const timer = window.setInterval(() => {
      setCurrentTime(new Date());
    }, 1000);
    return () => window.clearInterval(timer);
  }, []);

  const formattedDate = currentTime.toLocaleDateString(undefined, {
    weekday: 'long',
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  });

  const formattedTime = currentTime.toLocaleTimeString(undefined, {
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  });

  return (
    <header className="w-full bg-slate-900/90 border-b border-slate-800 backdrop-blur-md px-6 py-4 flex flex-col md:flex-row items-center justify-between gap-4 shadow-lg shrink-0">
      {/* Clinic Identity */}
      <div className="flex items-center gap-4">
        <div className="w-12 h-12 rounded-xl bg-gradient-to-tr from-cyan-600 to-blue-500 flex items-center justify-center shadow-md shadow-cyan-900/40 border border-cyan-400/30">
          <Activity className="w-7 h-7 text-white" />
        </div>
        <div>
          <h1 className="text-2xl md:text-3xl font-extrabold tracking-tight text-white m-0">
            {clinicName}
          </h1>
          <p className="text-xs md:text-sm text-cyan-400 font-medium tracking-wide uppercase m-0 flex items-center gap-1.5">
            <span className="w-2 h-2 rounded-full bg-emerald-400 animate-pulse inline-block" />
            Waiting Room Display
          </p>
        </div>
      </div>

      {/* Clock and Live Status */}
      <div className="flex items-center gap-4 bg-slate-800/80 border border-slate-700/60 px-5 py-2.5 rounded-xl shadow-inner">
        <Clock className="w-5 h-5 text-cyan-400 shrink-0" />
        <div className="text-right">
          <div className="text-xl md:text-2xl font-bold font-mono text-white tracking-wider">
            {formattedTime}
          </div>
          <div className="text-xs text-slate-400 font-medium">
            {formattedDate}
          </div>
        </div>
      </div>
    </header>
  );
};
