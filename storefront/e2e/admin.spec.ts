import { expect, test, type Page } from '@playwright/test';

// The dashboard over the built-in test data. The tests share one in-memory
// store with the shop, so they run in order, on one screen size.
test.describe.configure({ mode: 'serial' });
test.skip(({ isMobile }) => isMobile, 'Dashboard flows run once, on desktop');

async function signIn(page: Page) {
  await page.goto('/admin');
  await page.getByLabel('Email').fill('owner@animeyay.test');
  await page.getByLabel('Password').fill('otaku-admin');
  await page.getByRole('button', { name: 'Sign in' }).click();
  await expect(page.getByRole('heading', { name: 'Dashboard' })).toBeVisible();
}

test('the dashboard needs the owner to sign in', async ({ page }) => {
  await page.goto('/admin/orders');
  await expect(page).toHaveURL(/\/admin\/login\?next=%2Fadmin%2Forders/);
  await page.getByLabel('Email').fill('owner@animeyay.test');
  await page.getByLabel('Password').fill('wrong');
  await page.getByRole('button', { name: 'Sign in' }).click();
  await expect(page.getByText('Wrong email or password')).toBeVisible();

  const api = await page.request.post('/api/admin/sales', { data: {} });
  expect(api.status()).toBe(401);
});

test('a website order is confirmed, paid and takes stock', async ({ page }) => {
  // Customer orders a size M jersey on the website.
  await page.goto('/p/p4');
  await expect(page.getByRole('button', { name: 'Size S, sold out' })).toBeDisabled();
  await page.getByRole('button', { name: 'Size M', exact: true }).click();
  await page.getByRole('button', { name: /Add to Cart/ }).click();
  await page.goto('/cart');
  await page.getByPlaceholder('Your name').fill('Bupe');
  await page.getByPlaceholder(/Phone number/).fill('0961234567');
  await page.getByRole('button', { name: 'Order on WhatsApp' }).click();
  await expect(page).toHaveURL(/\/order\//);
  const code = page.url().split('/').pop()!;

  await signIn(page);
  await page.getByRole('link', { name: /New orders/ }).click();
  await page.getByRole('link', { name: new RegExp(`Bupe[\\s\\S]*${code}`) }).click();
  await expect(page.getByRole('heading', { name: code })).toBeVisible();

  await page.getByRole('button', { name: 'Confirm order' }).click();
  await expect(page.getByRole('status')).toHaveText('Marked confirmed');

  // The amount starts as what's owed: K250 jersey + K30 delivery in the test shop.
  await expect(page.getByLabel('Amount (K)')).toHaveValue('280');
  await page.getByText('Cash', { exact: true }).click();
  await page.getByRole('button', { name: 'Save payment' }).click();
  await expect(page.getByRole('status')).toHaveText('K280 cash payment recorded');
  await expect(page.getByText('Fully paid')).toBeVisible();

  await page.goto('/admin/products/p4');
  await expect(page.getByText('M · has 1')).toBeVisible();

  // Cancelling puts it back.
  await page.goto(`/admin/orders/${code}`);
  page.once('dialog', (d) => d.accept());
  await page.getByRole('button', { name: 'Cancel order' }).click();
  await expect(page.getByRole('status')).toHaveText('Marked cancelled');
  await page.goto('/admin/products/p4');
  await expect(page.getByText('M · has 2')).toBeVisible();
});

test('recording an in-person sale with a part payment', async ({ page }) => {
  await signIn(page);
  await page.getByRole('link', { name: 'New sale' }).first().click();
  await page.getByRole('button', { name: /Zenitsu Jersey/ }).click();
  await page.getByRole('button', { name: 'Size L' }).click();
  await page.getByLabel('Customer name').fill('Mutale');
  await page.getByRole('button', { name: 'Part paid' }).click();
  await page.getByLabel('Amount paid').fill('100');
  await page.getByRole('button', { name: /Record sale · K250/ }).click();

  await expect(page.getByRole('status')).toHaveText('Sale recorded');
  await expect(page.getByText('In person', { exact: false })).toBeVisible();
  await expect(page.getByText('Still owed')).toBeVisible();
  await expect(page.getByText('K150', { exact: true })).toBeVisible();

  await page.goto('/admin/orders?owed=1');
  await expect(page.getByText('Mutale')).toBeVisible();
});

test('stock counts drive what the website shows', async ({ page }) => {
  await signIn(page);
  await page.goto('/admin/products/p1');
  await page.getByLabel('Stock count', { exact: true }).fill('1');
  await page.getByRole('button', { name: 'Set exact count' }).click();
  await expect(page.getByRole('status')).toHaveText('Stock counts saved');
  await expect(page.getByText('1 in stock')).toBeVisible();

  await page.goto('/p/p1');
  await expect(page.getByText('Only a few left')).toBeVisible();

  await page.goto('/admin/products/p1');
  await page.getByLabel('Stock count', { exact: true }).fill('0');
  await page.getByRole('button', { name: 'Set exact count' }).click();
  await page.goto('/p/p1');
  await expect(page.getByRole('button', { name: 'Sold out' })).toBeDisabled();

  // Restock for the other tests.
  await page.goto('/admin/products/p1');
  await page.getByLabel('Stock count', { exact: true }).fill('10');
  await page.getByRole('button', { name: 'Add new stock' }).click();
  await expect(page.getByRole('status')).toHaveText('New stock added');
});

test('adding a product', async ({ page }) => {
  await signIn(page);
  await page.goto('/admin/products/new');
  await page.getByLabel('Name', { exact: true }).fill('Luffy Straw Hat');
  await page.getByLabel('Price (K)', { exact: true }).fill('180');
  await page.getByRole('button', { name: 'Add product' }).click();
  await expect(page).toHaveURL(/\/admin\/products\/luffy-straw-hat/);
  await expect(page.getByRole('status')).toHaveText('Product added. Now add photos and stock.');
  await page.goto('/?q=straw');
  await expect(page.getByText('Luffy Straw Hat')).toBeVisible();
});

test('signing out', async ({ page }) => {
  await signIn(page);
  await page.getByRole('button', { name: 'Sign out' }).click();
  await expect(page).toHaveURL(/\/admin\/login/);
  await page.goto('/admin');
  await expect(page).toHaveURL(/\/admin\/login/);
});
