import type { Departure } from "@/app/types";

export const departures: Departure[] = [
  {
    time: "2024-01-15T10:05:00+01:00",
    realTime: false,
    delay: null,
  },
  {
    time: "2024-01-15T10:12:00+01:00",
    realTime: true,
    delay: 120,
  },
  {
    time: "2024-01-15T10:20:00+01:00",
    realTime: false,
    delay: null,
  },
  {
    time: "2024-01-15T10:30:00+01:00",
    realTime: true,
    delay: 0,
  },
];
