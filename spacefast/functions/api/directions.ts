import { walkingDirections } from "@/app/lib/directions";

export function GET(request: Request, { env }: { env: { MAPBOX_SECRET_TOKEN?: string } }): Promise<Response> {
  return walkingDirections(request, env.MAPBOX_SECRET_TOKEN);
}
