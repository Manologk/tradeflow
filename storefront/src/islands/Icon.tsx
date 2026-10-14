import { icons, type IconName } from '../lib/icons';

export function Icon({ name, size = 22, filled = false, class: className }: { name: IconName; size?: number; filled?: boolean; class?: string }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill={filled ? 'currentColor' : 'none'}
      stroke="currentColor"
      stroke-width="1.8"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
      class={className}
    >
      <path d={icons[name]} />
    </svg>
  );
}
