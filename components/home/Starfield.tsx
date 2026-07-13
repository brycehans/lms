import { Moon, Sparkle, Star } from "lucide-react";

/**
 * Purely decorative celestial backdrop for the hero — a faint crescent moon and
 * a scattering of stars in the brand green. Absolutely positioned and
 * aria-hidden so it never interferes with layout or screen readers.
 */

type Speck = {
  top: string;
  left: string;
  size: number;
  opacity: number;
  icon: "star" | "sparkle";
};

// Hand-placed so the scatter reads as intentional constellation, not noise.
const SPECKS: Speck[] = [
  { top: "18%", left: "8%", size: 20, opacity: 0.35, icon: "sparkle" },
  { top: "62%", left: "14%", size: 14, opacity: 0.25, icon: "star" },
  { top: "78%", left: "26%", size: 10, opacity: 0.2, icon: "sparkle" },
  { top: "30%", left: "22%", size: 12, opacity: 0.3, icon: "star" },
  { top: "12%", left: "44%", size: 10, opacity: 0.25, icon: "sparkle" },
  { top: "82%", left: "52%", size: 14, opacity: 0.2, icon: "star" },
  { top: "24%", left: "68%", size: 12, opacity: 0.3, icon: "sparkle" },
  { top: "70%", left: "78%", size: 18, opacity: 0.3, icon: "star" },
  { top: "44%", left: "88%", size: 12, opacity: 0.28, icon: "sparkle" },
  { top: "16%", left: "82%", size: 10, opacity: 0.22, icon: "star" },
];

export function Starfield() {
  return (
    <div aria-hidden className="pointer-events-none absolute inset-0 text-primary">
      <Moon
        size={140}
        strokeWidth={1}
        className="absolute -right-6 -top-10 rotate-12 text-primary/10"
      />
      {SPECKS.map((s, i) => {
        const Icon = s.icon === "star" ? Star : Sparkle;
        return (
          <Icon
            key={i}
            size={s.size}
            className="absolute"
            style={{ top: s.top, left: s.left, opacity: s.opacity }}
            fill="currentColor"
            strokeWidth={0}
          />
        );
      })}
    </div>
  );
}
