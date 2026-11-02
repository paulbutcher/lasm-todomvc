// Copyright (c) 2026 Paul Butcher. All rights reserved.
// Released under Apache 2.0 license as described in the file LICENSE.

// The chat in a browser, against a stand-in for the Anthropic API. What `update` does with a reply
// is pure and checked in Lean; these check what only a browser can show: the request that leaves,
// storage across a reload, the keyboard, and what reaches the DOM.

import { test, expect } from '@playwright/test';

const api = 'https://api.anthropic.com/v1/messages';

const cors = {
  'access-control-allow-origin': '*',
  'access-control-allow-headers': '*',
  'access-control-allow-methods': 'POST',
};

/** Answers each request with the next of `replies`, recording what was sent. */
async function mockClaude(page, replies) {
  const requests = [];
  await page.route(api, async route => {
    const req = route.request();
    if (req.method() === 'OPTIONS') return route.fulfill({ status: 204, headers: cors });
    requests.push({ headers: req.headers(), body: req.postDataJSON() });
    const reply = replies.shift() ?? { status: 500, body: { error: { message: 'no more replies' } } };
    await route.fulfill({
      status: reply.status ?? 200,
      headers: { ...cors, 'content-type': 'application/json' },
      body: JSON.stringify(reply.body),
    });
  });
  return requests;
}

const toolUse = (id, name, input) =>
  ({ body: { content: [{ type: 'tool_use', id, name, input }], stop_reason: 'tool_use' } });
const said = text => ({ body: { content: [{ type: 'text', text }], stop_reason: 'end_turn' } });

const prompt = page => page.locator('#chat-prompt');
const todos = page => page.locator('.todo-list li label');

async function enterKey(page) {
  await page.locator('#chat-key').fill('sk-test');
  await page.locator('.chat-key .chat-send').click();
  await expect(prompt(page)).toBeVisible();
}

test.beforeEach(async ({ page }) => {
  await page.goto('/');
});

test('asks for a key first, and keeps it for the session only', async ({ page, context, browser }) => {
  await expect(page.locator('#chat-key')).toBeVisible();
  await expect(prompt(page)).toHaveCount(0);
  await enterKey(page);
  await page.reload();
  await expect(prompt(page)).toBeVisible();

  const other = await browser.newContext();
  const fresh = await other.newPage();
  await fresh.goto(page.url());
  await expect(fresh.locator('#chat-key')).toBeVisible();
  await other.close();
});

test('a turn runs tools against the list and shows the reply', async ({ page }) => {
  await page.locator('#new-todo').fill('Walk the dog');
  await page.locator('#new-todo').press('Enter');
  const requests = await mockClaude(page, [
    toolUse('t1', 'list_todos', {}),
    toolUse('t2', 'add_todo', { title: 'Buy milk' }),
    said('Added **Buy milk**.'),
  ]);
  await enterKey(page);
  await prompt(page).fill('Add milk');
  await page.locator('.chat-panel .chat-send').click();

  await expect(page.locator('.from-assistant strong')).toHaveText('Buy milk');
  await expect(todos(page)).toHaveText(['Walk the dog', 'Buy milk']);
  await expect(page.locator('.chat-tool-name')).toHaveText(['list_todos', 'add_todo']);

  expect(requests).toHaveLength(3);
  expect(requests[0].headers['x-api-key']).toBe('sk-test');
  expect(requests[0].headers['anthropic-dangerous-direct-browser-access']).toBe('true');
  const listed = requests[1].body.messages.at(-1).content[0];
  expect(listed).toMatchObject({ type: 'tool_result', tool_use_id: 't1' });
  expect(JSON.stringify(listed.content)).toContain('Walk the dog');
});

test('the conversation and the list survive a reload', async ({ page }) => {
  await mockClaude(page, [toolUse('t1', 'add_todo', { title: 'Water plants' }), said('Done.')]);
  await enterKey(page);
  await prompt(page).fill('Remind me to water the plants');
  await prompt(page).press('Enter');
  await expect(page.locator('.from-assistant .chat-bubble')).toHaveText('Done.');

  await page.reload();
  await expect(page.locator('.from-user .chat-bubble')).toHaveText('Remind me to water the plants');
  await expect(page.locator('.from-assistant .chat-bubble')).toHaveText('Done.');
  await expect(todos(page)).toHaveText(['Water plants']);

  await page.locator('.chat-reset', { hasText: 'New chat' }).click();
  await page.reload();
  await expect(page.locator('.chat-empty')).toBeVisible();
});

test('Enter sends and Shift+Enter starts a new line', async ({ page }) => {
  const requests = await mockClaude(page, [said('Noted.')]);
  await enterKey(page);
  await prompt(page).click();
  await page.keyboard.type('first');
  await page.keyboard.press('Shift+Enter');
  await page.keyboard.type('second');
  await expect(prompt(page)).toHaveValue('first\nsecond');
  await page.keyboard.press('Enter');

  await expect(page.locator('.from-assistant .chat-bubble')).toHaveText('Noted.');
  await expect(prompt(page)).toHaveValue('');
  expect(requests[0].body.messages.at(-1).content).toContain('first\nsecond');
});

test('a failed request is reported and its prompt kept to try again', async ({ page }) => {
  await mockClaude(page, [{ status: 401, body: { error: { type: 'authentication_error', message: 'invalid x-api-key' } } }]);
  await enterKey(page);
  await prompt(page).fill('Hello');
  await prompt(page).press('Enter');
  await expect(page.locator('.chat-error')).toContainText('invalid x-api-key');
  await expect(prompt(page)).toHaveValue('Hello');
});

test('markup in a reply is not run', async ({ page }) => {
  await mockClaude(page, [said('<img src=x onerror="window.pwned=1"> [link](javascript:window.pwned=2) <script>window.pwned=3</script>')]);
  await enterKey(page);
  await prompt(page).fill('Hi');
  await prompt(page).press('Enter');
  await expect(page.locator('.from-assistant .chat-bubble')).toBeVisible();
  await expect(page.locator('.chat-bubble img, .chat-bubble script')).toHaveCount(0);
  const hrefs = await page.locator('.chat-bubble a').evaluateAll(as => as.map(a => a.getAttribute('href') ?? ''));
  expect(hrefs.every(h => !h.startsWith('javascript:'))).toBe(true);
  expect(await page.evaluate(() => window.pwned)).toBeUndefined();
});

test('the divider resizes the panel', async ({ page }) => {
  const panel = page.locator('#chat-panel');
  const before = (await panel.boundingBox()).width;
  const divider = (await page.locator('.app-divider').boundingBox());
  await page.mouse.move(divider.x + 2, divider.y + 100);
  await page.mouse.down();
  await page.mouse.move(divider.x - 150, divider.y + 100, { steps: 5 });
  await page.mouse.up();
  await expect.poll(async () => (await panel.boundingBox()).width).toBeGreaterThan(before + 100);
});
