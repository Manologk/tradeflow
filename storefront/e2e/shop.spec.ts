import { expect, test, type Page } from '@playwright/test';

const product = (page: Page, name: string) => page.getByRole('link', { name: new RegExp(name) }).first();

test('lists in-stock, pre-order and sold-out merch', async ({ page }) => {
  await page.goto('/');
  await expect(page.getByRole('heading', { name: 'Otaku Corner' })).toBeVisible();
  await expect(product(page, 'Naruto Sage Mode Figure')).toBeVisible();
  await expect(product(page, 'Gojo Hoodie')).toBeVisible();
  await expect(product(page, 'Itachi Keychain')).toBeVisible();
});

test('filters by category and search', async ({ page }) => {
  await page.goto('/');
  await page.getByRole('link', { name: 'Clothing' }).click();
  await expect(page).toHaveURL(/category=/);
  await expect(product(page, 'Gojo Hoodie')).toBeVisible();
  await expect(page.getByText('Naruto Sage Mode Figure')).toHaveCount(0);

  await page.goto('/?q=keychain');
  await expect(product(page, 'Itachi Keychain')).toBeVisible();
  await expect(page.getByText('Gojo Hoodie')).toHaveCount(0);
});

test('unknown product is a 404', async ({ page }) => {
  const res = await page.goto('/p/nope');
  expect(res?.status()).toBe(404);
});

test('asks for a size and colour before adding to the cart', async ({ page }) => {
  await page.goto('/p/p2');
  const add = page.getByRole('button', { name: /Pre-order \| K380/ });
  await add.click();
  await expect(page.getByRole('status')).toHaveText('Choose a size');
  await page.getByRole('button', { name: 'Size L' }).click();
  await add.click();
  await expect(page.getByRole('status')).toHaveText('Choose a colour');
  await page.getByRole('button', { name: 'Colour Black' }).click();
  await page.getByRole('button', { name: 'More', exact: true }).click();
  await page.getByRole('button', { name: /Pre-order \| K760/ }).click();
  await expect(page.getByRole('status')).toContainText('Added 2 × Gojo Hoodie');
  await page.goto('/');
  await expect(page.getByRole('link', { name: 'Cart, 2 items' })).toBeVisible();
});

test('sold-out items cannot be ordered', async ({ page }) => {
  await page.goto('/p/p3');
  await expect(page.getByRole('button', { name: 'Sold out' })).toBeDisabled();
});

test('checkout sends the order and hands over to WhatsApp', async ({ page }) => {
  await page.goto('/p/p1');
  await page.getByRole('button', { name: /Add to Cart/ }).click();
  await page.getByRole('link', { name: 'View cart' }).click();

  await expect(page.getByText('Total (1 item)')).toBeVisible();
  await page.getByRole('button', { name: 'Order on WhatsApp' }).click();
  await expect(page.getByText('Enter your name')).toBeVisible();

  await page.getByPlaceholder('Your name').fill('Mwila');
  await page.getByPlaceholder(/Phone number/).fill('097 123 4567');
  await page.getByRole('button', { name: 'Order on WhatsApp' }).click();

  await expect(page).toHaveURL(/\/order\/[A-Z0-9-]+$/);
  await expect(page.getByRole('heading', { name: 'One more step' })).toBeVisible();
  const whatsapp = page.getByRole('link', { name: 'Send on WhatsApp' });
  await expect(whatsapp).toHaveAttribute('href', /^https:\/\/wa\.me\//);
  const code = page.url().split('/').pop()!;

  await page.goto('/orders');
  await expect(page.getByText(code)).toBeVisible();
  await expect(page.getByRole('link', { name: 'Cart', exact: true })).toBeVisible();
});

test('favourites are remembered', async ({ page }) => {
  await page.goto('/favourites');
  await expect(page.getByRole('heading', { name: 'No favourites yet' })).toBeVisible();
  await page.goto('/p/p1');
  await page.getByRole('button', { name: 'Add to favourites' }).click();
  await page.goto('/favourites');
  await expect(product(page, 'Naruto Sage Mode Figure')).toBeVisible();
});

test('pages never scroll sideways', async ({ page }) => {
  for (const path of ['/', '/p/p2', '/cart', '/browse', '/orders', '/favourites']) {
    await page.goto(path);
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
    expect(overflow, path).toBeLessThanOrEqual(0);
  }
});

test('hovering a product offers quick buy (desktop)', async ({ page, isMobile }) => {
  test.skip(isMobile, 'Phones have no hover; they open the product page.');
  await page.goto('/');
  // Products with colours still need the product page.
  await expect(page.locator('[data-quick="p2"]')).toHaveCount(0);

  const card = page.locator('li', { has: page.locator('[data-quick="p1"]') });
  await card.hover();
  await card.getByRole('button', { name: /Add Naruto Sage Mode Figure to cart/ }).click();
  await expect(page.getByRole('link', { name: 'Cart, 1 items' })).toBeVisible();
  await card.getByRole('button', { name: /Buy now/ }).click();
  await expect(page).toHaveURL(/\/cart$/);
  await expect(page.getByText('Total (2 items)')).toBeVisible();
});
