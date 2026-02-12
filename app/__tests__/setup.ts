import "@testing-library/jest-dom/vitest";
import { setupServer } from "msw/node";
import { handlers } from "./mocks/handlers";
import { beforeAll, afterAll, afterEach, vi } from "vitest";

// MSW server
export const server = setupServer(...handlers);

beforeAll(() => server.listen({ onUnhandledRequest: "warn" }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

// Mock react-map-gl
vi.mock("react-map-gl", () => import("./mocks/react-map-gl"));

// Mock mapbox-gl (no WebGL in jsdom)
vi.mock("mapbox-gl", () => import("./mocks/mapbox-gl"));

// Stub environment variables
vi.stubEnv("HERE_API_KEY", "test-here-api-key");
vi.stubEnv("MAPBOX_SECRET_TOKEN", "sk.test-mapbox-secret");
vi.stubEnv("NEXT_PUBLIC_MAPBOX_TOKEN", "pk.test-mapbox-public");
vi.stubEnv("NEXT_PUBLIC_SEARCH_RADIUS", "250");
