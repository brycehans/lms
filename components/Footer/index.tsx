import { cacheLife } from "next/cache";

export async function Footer() {
    'use cache';

    const now = new Date();
    const nextYearTS = Date.parse(`${now.getFullYear()+1}-01-01`);

    const msTilNextYear = nextYearTS - now.getTime();

    cacheLife({
        expire: msTilNextYear
    });
    
    return (
        <footer className="w-full flex items-center justify-center border-t mx-auto text-center text-xs gap-8 py-16">
          &copy; {new Date().getFullYear()} Bryce Hanscomb
        </footer>
    )
}