import React from 'react';
import { useParams } from 'react-router-dom';
import { DisplayEmptyState } from '../components/display/DisplayEmptyState';
import { DisplayErrorState } from '../components/display/DisplayErrorState';
import { DisplayHeader } from '../components/display/DisplayHeader';
import { DisplayLoadingState } from '../components/display/DisplayLoadingState';
import { QueueCard } from '../components/display/QueueCard';
import { usePublicDisplay } from '../hooks/usePublicDisplay';

export const PublicDisplayPage: React.FC = () => {
  const { clinicId } = useParams<{ clinicId: string }>();
  const { data, loading, error, lastUpdated, refetch } = usePublicDisplay(clinicId);

  if (loading && !data) {
    return (
      <main className="min-h-screen w-screen bg-slate-950 text-white flex flex-col">
        <DisplayLoadingState />
      </main>
    );
  }

  if (error && !data) {
    return (
      <main className="min-h-screen w-screen bg-slate-950 text-white flex flex-col">
        <DisplayErrorState message={error} onRetry={refetch} />
      </main>
    );
  }

  if (!data) {
    return (
      <main className="min-h-screen w-screen bg-slate-950 text-white flex flex-col">
        <DisplayErrorState message="Unable to load queue information" onRetry={refetch} />
      </main>
    );
  }

  const { clinic, queues } = data;

  // Compute adaptive grid column styling based on queue count
  const getGridClasses = (count: number) => {
    if (count === 1) {
      return 'grid-cols-1 max-w-3xl mx-auto';
    }
    if (count === 2) {
      return 'grid-cols-1 lg:grid-cols-2 max-w-6xl mx-auto';
    }
    if (count === 3) {
      return 'grid-cols-1 md:grid-cols-2 xl:grid-cols-3';
    }
    return 'grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4';
  };

  return (
    <main className="min-h-screen w-screen bg-slate-950 text-white flex flex-col selection:bg-cyan-500 selection:text-white">
      {/* Top Header */}
      <DisplayHeader clinicName={clinic.name} />

      {/* Main Content Area */}
      <section className="flex-1 p-6 md:p-8 flex flex-col justify-start overflow-y-auto">
        {queues.length === 0 ? (
          <DisplayEmptyState />
        ) : (
          <div className={`grid ${getGridClasses(queues.length)} gap-6 w-full items-stretch`}>
            {queues.map((q) => (
              <QueueCard
                key={q.doctor.id}
                queue={q}
                serverTime={data.server_time}
                fetchedAtMs={lastUpdated ? lastUpdated.getTime() : null}
              />
            ))}
          </div>
        )}
      </section>
    </main>
  );
};
