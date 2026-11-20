import React from 'react';
import { DentalLogo } from '../common/DentalLogo';

export const DisplayLoadingState: React.FC = () => {
  return (
    <div className="flex-1 flex flex-col items-center justify-center p-10 text-center bg-[#071422]">
      <div className="relative mb-6 flex items-center justify-center">
        <div className="w-20 h-20 rounded-full border-4 border-[#1A3047] border-t-[#2DD4BF] animate-spin" />
        <DentalLogo size="md" className="absolute" />
      </div>
      <h2 className="text-2xl md:text-3xl font-extrabold text-[#F1F5F9] tracking-tight mb-2">
        Loading queue...
      </h2>
      <p className="text-[#A5B4C7] text-sm md:text-base font-medium">
        Connecting to queue system
      </p>
    </div>
  );
};
