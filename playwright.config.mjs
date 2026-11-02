// Copyright (c) 2026 Paul Butcher. All rights reserved.
// Released under Apache 2.0 license as described in the file LICENSE.

import { defineConfig } from '@playwright/test';

const port = 5174;

export default defineConfig({
  testDir: 'e2e',
  timeout: 30_000,
  use: { baseURL: `http://127.0.0.1:${port}/` },
  webServer: {
    command: `npx lasm dev Main.lean --target browser --no-watch --port ${port} --output .lake/e2e`,
    url: `http://127.0.0.1:${port}/`,
    timeout: 600_000,
    reuseExistingServer: false,
  },
});
