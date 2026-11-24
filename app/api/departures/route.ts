import { departures } from "@/app/lib/departures";

export function GET(request: Request): Promise<Response> {
  return departures(request, process.env.HERE_API_KEY);
}
