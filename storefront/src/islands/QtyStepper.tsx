import { Icon } from './Icon';

export function QtyStepper({ value, onChange, min = 1, max = 99, label = '' }: { value: number; onChange: (v: number) => void; min?: number; max?: number; label?: string }) {
  const btn = 'grid size-8 place-items-center rounded-full border border-line bg-white disabled:opacity-40';
  return (
    <div class="flex items-center">
      <button type="button" class={btn} disabled={value <= min} aria-label={`Less ${label}`.trim()} onClick={() => onChange(value - 1)}>
        <Icon name="minus" size={16} />
      </button>
      <span class="w-8 text-center text-base font-semibold tabular-nums" aria-live="polite">{value}</span>
      <button type="button" class={btn} disabled={value >= max} aria-label={`More ${label}`.trim()} onClick={() => onChange(value + 1)}>
        <Icon name="plus" size={16} />
      </button>
    </div>
  );
}
