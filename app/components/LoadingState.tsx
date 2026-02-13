export function LoadingState(props: { message?: string }) {
  const message = props.message ?? "Finding nearby stops...";

  return (
    <div
      role="status"
      aria-label={message}
      className="flex min-h-[50vh] flex-col items-center justify-center gap-3"
    >
      <div className="h-8 w-8 animate-spin rounded-full border-2 border-zinc-300 border-t-blue-600" />
      <p>{message}</p>
    </div>
  );
}
