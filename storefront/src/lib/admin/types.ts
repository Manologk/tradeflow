import type { Availability, OrderStatus, ShopCategory, ShopColor, ShopSeries } from '../models';

// What the owner sees and edits in the dashboard. Money is ngwee (K1 = 100).

export type PaymentMethod = 'cash' | 'mobile_money';

export interface AdminPayment {
  id: number;
  amountZmw: number;
  method: PaymentMethod;
  note: string;
  paidAt: string;
}

export interface AdminOrderItem {
  productId: string;
  name: string;
  size: string | null;
  color: string | null;
  qty: number;
  unitPriceZmw: number;
  preOrder: boolean;
}

export interface AdminOrder {
  code: string;
  createdAt: string;
  /** 'website' orders come from the shop; 'shop' sales were recorded in the dashboard. */
  source: 'website' | 'shop';
  status: OrderStatus;
  customerName: string;
  phone: string | null;
  areaName: string | null;
  notes: string;
  itemsZmw: number;
  deliveryZmw: number;
  depositZmw: number;
  items: AdminOrderItem[];
  payments: AdminPayment[];
}

export const orderTotal = (o: AdminOrder) => o.itemsZmw + o.deliveryZmw;
export const orderPaid = (o: AdminOrder) => o.payments.reduce((s, p) => s + p.amountZmw, 0);
export const orderOwed = (o: AdminOrder) => Math.max(0, orderTotal(o) - orderPaid(o));

export interface AdminProduct {
  id: string;
  name: string;
  description: string;
  categoryId: string;
  seriesId: string | null;
  priceZmw: number;
  compareAtZmw: number | null;
  photos: string[];
  sizes: string[];
  colors: ShopColor[];
  availability: Availability;
  leadTimeWeeks: number | null;
  published: boolean;
  /** On: availability follows the stock counts. Off: set by hand. */
  trackStock: boolean;
  /** Count per size; '' for products without sizes. */
  stock: Record<string, number>;
  sortOrder: number;
}

/** Units in stock across the sizes the product sells. */
export function stockTotal(p: AdminProduct): number {
  const keys = p.sizes.length ? p.sizes : [''];
  return keys.reduce((s, k) => s + (p.stock[k] ?? 0), 0);
}

export interface ProductInput {
  id: string;
  name: string;
  description: string;
  categoryId: string;
  seriesId: string | null;
  priceZmw: number;
  compareAtZmw: number | null;
  photos: string[];
  sizes: string[];
  /** Only used when stock isn't tracked, or for pre-orders. */
  availability: Availability;
  leadTimeWeeks: number | null;
  published: boolean;
}

export interface SaleInput {
  customer: { name: string; phone: string | null };
  notes: string;
  status: 'confirmed' | 'ready' | 'delivered';
  lines: { productId: string; size: string | null; qty: number; unitPriceZmw: number }[];
  payment: { amountZmw: number; method: PaymentMethod } | null;
}

export interface AdminSummary {
  salesToday: number;
  salesWeek: number;
  salesMonth: number;
  ordersMonth: number;
  receivedMonth: number;
  owed: number;
  newOrders: number;
  toDeliver: number;
  lowStock: { productId: string; name: string; size: string | null; qty: number }[];
  topSellers: { name: string; qty: number }[];
}

/** Everything the dashboard can do, for the signed-in owner. */
export interface AdminApi {
  summary(): Promise<AdminSummary>;
  orders(filter: { status?: OrderStatus | 'open'; limit?: number }): Promise<AdminOrder[]>;
  order(code: string): Promise<AdminOrder | null>;
  setStatus(code: string, status: OrderStatus): Promise<void>;
  addPayment(code: string, amountZmw: number, method: PaymentMethod, note: string): Promise<void>;
  deletePayment(id: number): Promise<void>;
  recordSale(sale: SaleInput): Promise<string>;
  products(): Promise<AdminProduct[]>;
  product(id: string): Promise<AdminProduct | null>;
  lists(): Promise<{ categories: ShopCategory[]; series: ShopSeries[] }>;
  saveProduct(p: ProductInput): Promise<void>;
  setStock(productId: string, size: string, qty: number, reason: 'restock' | 'correction'): Promise<void>;
  /** Stops following stock counts, going back to a hand-set availability. */
  stopTracking(productId: string): Promise<void>;
  uploadPhoto(productId: string, data: ArrayBuffer, contentType: string): Promise<string>;
}

/** A refusal the owner should read (e.g. "Not enough stock: …"). */
export class AdminError extends Error {}
