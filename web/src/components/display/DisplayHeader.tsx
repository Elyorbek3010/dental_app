import React, { useEffect, useState } from 'react';
import { Clock } from 'lucide-react';
import { DentalLogo } from '../common/DentalLogo';

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
    <header className="w-full bg-[#0B1728]/95 border-b border-[#1E354E] backdrop-blur-md px-6 lg:px-10 py-4 flex flex-col md:flex-row items-center justify-between gap-4 shadow-xl shrink-0">
      {/* Clinic Identity */}
      <div className="flex items-center gap-4">
        <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-[#12243A] border border-[#253F5B] shadow-md">
          <DentalLogo size="md" />
        </div>
        <div>
          <h1 className="text-2xl md:text-3xl font-extrabold tracking-tight text-[#F1F5F9] m-0">
            {clinicName}
          </h1>
          <p className="text-xs md:text-sm text-[#2DD4BF] font-semibold tracking-wider uppercase m-0 mt-0.5 flex items-center gap-2">
            <span className="w-2 h-2 rounded-full bg-emerald-400 animate-pulse inline-block" />
            Waiting Room Display
          </p>
        </div>
      </div>

      {/* Clock and Live Status */}
      <div className="flex items-center gap-3.5 bg-[#12243A] border border-[#253F5B] px-5 py-2.5 rounded-2xl shadow-inner">
        <Clock className="w-5 h-5 text-[#38BDF8] shrink-0" />
        <div className="text-right">
          <div className="text-xl md:text-2xl font-extrabold font-mono text-[#F1F5F9] tracking-wider tabular-nums">
            {formattedTime}
          </div>
          <div className="text-xs text-[#A5B4C7] font-medium">
            {formattedDate}
          </div>
        </div>
      </div>
    </header>
  );
};
