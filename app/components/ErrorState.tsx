const messages: Record<string, string> = {
  permission: "Location permission required",
  network: "Couldn't load stops",
  timeout: "Taking too long to find your location",
  empty: "No public transit stops nearby",
  offline: "You appear to be offline",
};

const descriptions: Record<string, string> = {
  permission: "Departs needs your location to find nearby transit stops. Please enable location access in your browser settings.",
  network: "We couldn't connect to the transit data service. Check your connection and try again.",
  timeout: "Your device is taking longer than expected to determine your location.",
  empty: "We couldn't find any stops within 250m. Try moving to a different area.",
  offline: "Check your internet connection and try again.",
};

export function ErrorState({
  type,
  onRetry,
}: {
  type: "permission" | "network" | "timeout" | "empty" | "offline";
  onRetry: () => void;
}) {
  return (
    <div
      className="flex flex-col items-center gap-3 text-center"
      style={{
        height: "100dvh",
        justifyContent: "center",
        padding: "24px",
        backgroundColor: "var(--color-bg-secondary)",
      }}
    >
      <p
        className="font-semibold"
        style={{ fontSize: "17px", color: "var(--color-text-primary)" }}
      >
        {messages[type]}
      </p>
      <p style={{ fontSize: "15px", color: "var(--color-text-secondary)" }}>
        {descriptions[type]}
      </p>
      {type !== "empty" && (
        <button
          onClick={onRetry}
          className="px-5 py-2.5 rounded-full"
          style={{
            marginTop: "8px",
            backgroundColor: "var(--color-accent)",
            color: "#FFFFFF",
            fontSize: "17px",
            fontWeight: 600,
          }}
        >
          Retry
        </button>
      )}
    </div>
  );
}
