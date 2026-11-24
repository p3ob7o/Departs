import { nearbyStops } from "@/app/lib/nearby";

export function GET(request: Request): Promise<Response> {
  return nearbyStops(request, process.env.HERE_API_KEY);
}
