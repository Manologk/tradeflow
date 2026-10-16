declare namespace App {
  interface Locals {
    /** Set by the middleware once the shop owner is signed in. */
    admin?: import('./lib/admin/types').AdminApi;
    adminEmail?: string;
  }
}
