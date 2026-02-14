export function LoadingState({ message }: { message?: string }) {
  return (
    <div
      role="status"
      aria-label="Loading"
      className="flex flex-col items-center justify-center gap-4"
      style={{ height: "100dvh", backgroundColor: "var(--color-bg-secondary)" }}
    >
      <div
        className="animate-spin h-8 w-8 border-4 rounded-full"
        style={{
          borderColor: "var(--color-bg-tertiary)",
          borderTopColor: "var(--color-text-primary)",
        }}
      />
      <p style={{ fontSize: "15px", color: "var(--color-text-secondary)" }}>
        {message || "Finding nearby stops..."}
      </p>
    </div>
  );
}
