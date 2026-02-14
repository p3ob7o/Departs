export function BottomSheet({ children }: { children: React.ReactNode }) {
  return (
    <div
      data-testid="bottom-sheet"
      className="rounded-t-2xl px-4 overflow-y-auto"
      style={{
        paddingBottom: "env(safe-area-inset-bottom)",
        backgroundColor: "var(--color-bg-primary)",
      }}
    >
      <div className="pt-2 pb-6 flex justify-center">
        <div
          data-testid="drag-handle"
          className="rounded-full"
          style={{
            width: "36px",
            height: "5px",
            backgroundColor: "var(--color-bg-tertiary)",
          }}
        />
      </div>
      {children}
    </div>
  );
}
