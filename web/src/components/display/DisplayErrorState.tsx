import React from 'react';
import { AlertTriangle, RefreshCw } from 'lucide-react';

interface DisplayErrorStateProps {
  message?: string;
  onRetry?: () => void;
}

export const DisplayErrorState: React.FC<DisplayErrorStateProps> = ({
  message = 'Unable to load queue information',
  onRetry,
}) => {
  return (
    <div className="flex-1 flex flex-col items-center justify-center p-10 text-center bg-[#071422] animate-dental-in">
      <div className="w-24 h-24 rounded-3xl bg-rose-500/10 border border-rose-500/30 flex items-center justify-center mb-6 shadow-2xl">
        <AlertTriangle className="w-11 h-11 text-rose-400" />
      </div>
      <h2 className="text-2xl md:text-3xl font-extrabold text-[#F1F5F9] tracking-tight mb-2">
        {message}
      </h2>
      <p className="text-[#A5B4C7] text-sm md:text-base max-w-md font-medium mb-6">
        Please check clinic display settings or contact clinic reception for assistance.
      </p>

      {onRetry && (
        <button
          onClick={onRetry}
          className="inline-flex items-center gap-2 px-5 py-2.5 rounded-xl bg-[#1A3047] hover:bg-[#253F5B] text-[#F1F5F9] font-semibold text-sm border border-[#253F5B] transition-colors cursor-pointer"
        >
          <RefreshCw className="w-4 h-4 text-[#2DD4BF]" />
          Retry Connection
        </button>
      )}
    </div>
  );
};
