export function LoadingState({ message }: { message?: string }) {
  return (
    <div role="status" aria-label="Loading">
      <div className="animate-spin h-8 w-8 border-4 border-zinc-300 border-t-zinc-800 rounded-full" />
      <p>{message || "Finding nearby stops..."}</p>
    </div>
  );
}
