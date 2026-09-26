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
    <div className="flex-1 flex flex-col items-center justify-center p-8 text-center bg-slate-950">
      <div className="w-20 h-20 rounded-2xl bg-rose-500/10 border border-rose-500/20 flex items-center justify-center mb-6 shadow-xl shadow-rose-950/30">
        <AlertTriangle className="w-10 h-10 text-rose-400" />
      </div>
      <h2 className="text-2xl md:text-3xl font-bold text-white tracking-tight mb-2">
        {message}
      </h2>
      <p className="text-slate-400 text-sm md:text-base max-w-md font-medium mb-6">
        Please check clinic display settings or contact clinic reception for assistance.
      </p>

      {onRetry && (
        <button
          onClick={onRetry}
          className="inline-flex items-center gap-2 px-5 py-2.5 rounded-xl bg-slate-800 hover:bg-slate-700 text-white font-semibold text-sm border border-slate-700 transition-colors cursor-pointer"
        >
          <RefreshCw className="w-4 h-4" />
          Retry Connection
        </button>
      )}
    </div>
  );
};
