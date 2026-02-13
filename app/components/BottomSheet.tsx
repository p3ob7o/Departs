export function BottomSheet({ children }: { children: React.ReactNode }) {
  return (
    <div
      data-testid="bottom-sheet"
      className="rounded-t-2xl px-4 overflow-y-auto"
      style={{ paddingBottom: "env(safe-area-inset-bottom)" }}
    >
      <div data-testid="drag-handle" className="w-10 h-1 bg-zinc-300 rounded-full mx-auto my-2" />
      {children}
    </div>
  );
}
