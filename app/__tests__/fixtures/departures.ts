import type { Departure } from "@/app/types";

export const departures: Departure[] = [
  {
    time: "2024-01-15T10:05:00+01:00",
    line: { name: "U2", direction: "Pankow", type: "subway" },
    realTime: false,
    delay: null,
  },
  {
    time: "2024-01-15T10:14:00+01:00",
    line: { name: "U2", direction: "Pankow", type: "subway" },
    realTime: true,
    delay: 120,
  },
  {
    time: "2024-01-15T10:20:00+01:00",
    line: { name: "U2", direction: "Pankow", type: "subway" },
    realTime: false,
    delay: null,
  },
  {
    time: "2024-01-15T10:30:00+01:00",
    line: { name: "U2", direction: "Pankow", type: "subway" },
    realTime: true,
    delay: 0,
  },
];
