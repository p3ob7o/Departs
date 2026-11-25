import { departures } from "@/app/lib/departures";

export function GET(request: Request, { env }: { env: { HERE_API_KEY?: string } }): Promise<Response> {
  return departures(request, env.HERE_API_KEY);
}
