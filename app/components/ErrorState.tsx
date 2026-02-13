const messages: Record<string, string> = {
  permission: "Location permission required",
  network: "Couldn't load stops",
  timeout: "Taking too long to find your location",
  empty: "No public transit stops nearby",
  offline: "You appear to be offline",
};

export function ErrorState({
  type,
  onRetry,
}: {
  type: "permission" | "network" | "timeout" | "empty" | "offline";
  onRetry: () => void;
}) {
  return (
    <div className="flex flex-col items-center gap-4 p-6 text-center">
      <p>{messages[type]}</p>
      {type !== "empty" && (
        <button
          onClick={onRetry}
          className="px-4 py-2 rounded-full bg-zinc-800 text-white"
        >
          Retry
        </button>
      )}
    </div>
  );
}
