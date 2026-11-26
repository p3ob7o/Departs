import { setupServer } from "msw/node";
import { handlers } from "./mocks/handlers";
import { beforeAll, afterAll, afterEach, vi } from "vitest";

export const server = setupServer(...handlers);

beforeAll(() => server.listen({ onUnhandledRequest: "error" }));
afterEach(() => {
  vi.clearAllMocks();
  server.resetHandlers();
});
afterAll(() => server.close());

export const workerContext = {
  env: {
    HERE_API_KEY: "test-here-api-key",
    MAPBOX_SECRET_TOKEN: "sk.test-mapbox-secret",
  },
};
