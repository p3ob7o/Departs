import { departures } from "@/app/lib/departures";

export async function GET(request: Request, { env }: { env: { HERE_API_KEY?: string } }): Promise<Response> {
  const response = await departures(request, env.HERE_API_KEY);
  response.headers.set("Cache-Control", "no-store");
  return response;
}
