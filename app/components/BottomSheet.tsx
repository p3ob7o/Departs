export function BottomSheet({ children }: { children: React.ReactNode }) {
  return (
    <div
      data-testid="bottom-sheet"
      className="px-4 overflow-y-auto"
      style={{
        flex: "1 1 0%",
        minHeight: 0,
        paddingBottom: "env(safe-area-inset-bottom)",
        backgroundColor: "var(--color-bg-primary)",
      }}
    >
      {children}
    </div>
  );
}
