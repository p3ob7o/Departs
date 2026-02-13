import type { ReactNode } from "react";

export function BottomSheet(props: { children: ReactNode }) {
  return (
    <section
      data-testid="bottom-sheet"
      className="rounded-t-2xl bg-white px-4 pt-6 pb-4 overflow-y-auto dark:bg-zinc-900"
      style={{ paddingBottom: "env(safe-area-inset-bottom)" }}
    >
      <div className="mb-4 flex justify-center">
        <div
          data-testid="drag-handle"
          className="h-1 w-9 rounded-full bg-zinc-300 dark:bg-zinc-700"
        />
      </div>
      {props.children}
    </section>
  );
}
