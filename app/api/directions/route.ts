import { walkingDirections } from "@/app/lib/directions";

export function GET(request: Request): Promise<Response> {
  return walkingDirections(request, process.env.MAPBOX_SECRET_TOKEN);
}
