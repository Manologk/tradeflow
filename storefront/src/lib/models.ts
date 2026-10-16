// Shop-safe data published from the admin app. Costs and suppliers never
// appear here.

export type Availability = 'inStock' | 'fewLeft' | 'preOrder' | 'soldOut';

export interface ShopColor {
  name: string;
  /** e.g. "#292526" */
  hex: string;
}

export interface ShopProduct {
  id: string;
  name: string;
  description: string;
  categoryId: string;
  seriesId: string | null;
  /** Selling price in ngwee. */
  priceZmw: number;
  /** Previous price, shown struck through when higher than the price. */
  compareAtZmw: number | null;
  photos: string[];
  sizes: string[];
  /** Sizes with no stock left (the website greys these out). */
  soldOutSizes: string[];
  colors: ShopColor[];
  availability: Availability;
  /** For pre-orders: roughly how long until it arrives. */
  leadTimeWeeks: number | null;
}

export interface ShopCategory {
  id: string;
  name: string;
}

export interface ShopSeries {
  id: string;
  name: string;
  imageUrl: string | null;
}

export interface DeliveryArea {
  id: string;
  name: string;
  feeZmw: number;
}

export interface ShopSettings {
  name: string;
  /** International format, digits only, e.g. "260971234567". */
  whatsappNumber: string;
  deliveryAreas: DeliveryArea[];
  /** Share of a pre-order's value paid up front. */
  depositPercent: number;
  logoUrl: string | null;
}

export interface Catalog {
  settings: ShopSettings;
  categories: ShopCategory[];
  series: ShopSeries[];
  products: ShopProduct[];
}

/** One product (with chosen size/colour) in the cart. */
export interface CartLine {
  productId: string;
  size: string | null;
  color: string | null;
  qty: number;
}

export type OrderStatus = 'received' | 'confirmed' | 'ready' | 'delivered' | 'cancelled';

export interface Customer {
  name: string;
  /** International digits, e.g. "260971234567". */
  phone: string;
  areaId: string | null;
  notes: string;
}

/** A priced order line, frozen at the moment of ordering. */
export interface OrderLine {
  productId: string;
  name: string;
  size: string | null;
  color: string | null;
  qty: number;
  unitPriceZmw: number;
  preOrder: boolean;
  leadTimeWeeks: number | null;
}

export interface Order {
  code: string;
  createdAt: string;
  customer: Customer;
  areaName: string | null;
  lines: OrderLine[];
  itemsZmw: number;
  deliveryZmw: number;
  /** Due up front for pre-order items. */
  depositZmw: number;
}

export const canOrder = (p: ShopProduct) => p.availability !== 'soldOut';
export const isOnSale = (p: ShopProduct) => p.compareAtZmw !== null && p.compareAtZmw > p.priceZmw;
export const lineKey = (l: Pick<CartLine, 'productId' | 'size' | 'color'>) =>
  `${l.productId}|${l.size ?? ''}|${l.color ?? ''}`;
