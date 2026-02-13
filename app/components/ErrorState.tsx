const errorCopy = {
  permission: "Location permission is required to find nearby transit.",
  network: "Couldn't load transit data. Please try again.",
  timeout: "Finding your location is taking too long.",
  empty: "No public transit found within 250m.",
  offline: "You appear to be offline.",
} as const;

export function ErrorState(props: {
  type: "permission" | "network" | "timeout" | "empty" | "offline";
  onRetry: () => void;
}) {
  return (
    <div className="flex min-h-[50vh] flex-col items-center justify-center px-6 text-center">
      <p className="mb-4 text-base">{errorCopy[props.type]}</p>
      {props.type !== "empty" ? (
        <button
          type="button"
          onClick={props.onRetry}
          className="rounded-md bg-blue-600 px-4 py-2 text-white"
        >
          Retry
        </button>
      ) : null}
    </div>
  );
}
