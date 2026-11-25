import { nearbyStops } from "@/app/lib/nearby";

export function GET(request: Request, { env }: { env: { HERE_API_KEY?: string } }): Promise<Response> {
  return nearbyStops(request, env.HERE_API_KEY);
}
