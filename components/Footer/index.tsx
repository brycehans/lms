import { cacheLife } from "next/cache";
import { MoonStar } from "lucide-react";

export async function Footer() {
    'use cache';

    const now = new Date();
    const nextYearTS = Date.parse(`${now.getFullYear()+1}-01-01`);

    const msTilNextYear = nextYearTS - now.getTime();

    cacheLife({
        expire: msTilNextYear
    });

    return (
        <footer className="w-full flex flex-col items-center justify-center border-t mx-auto text-center gap-2 py-16">
          <p className="flex items-center gap-2 text-sm font-medium text-foreground">
            <MoonStar size={16} className="text-primary" />
            Gazing into your academic future since {new Date().getFullYear()}
          </p>
          <p className="text-xs text-muted-foreground">
            &copy; {new Date().getFullYear()} Bryce Hanscomb
          </p>
        </footer>
    )
}