// TODO: Implement error state component
export function ErrorState(_props: {
  type: "permission" | "network" | "timeout" | "empty" | "offline";
  onRetry: () => void;
}) {
  return null;
}
