import Image, { type StaticImageData } from "next/image";
import { Wand2 } from "lucide-react";
import { SectionHeading } from "@/components/home/SectionHeading";
import step1 from "./assets/step-1.webp";
import step2 from "./assets/step-2.webp";
import step3 from "./assets/step-3.webp";

type Step = {
  img: StaticImageData;
  title: string;
  body: string;
  alt: string;
};

const STEPS: Step[] = [
  {
    img: step1,
    title: "Book a consultation",
    body: "Sit down with one of our certified time travellers and hand over your course details.",
    alt: "A student consulting a robed time traveller over a glowing crystal ball.",
  },
  {
    img: step2,
    title: "They travel to the future",
    body: "They slip forward through time to the day your exam results are published.",
    alt: "A student glimpsed writing an exam through a swirling green time portal.",
  },
  {
    img: step3,
    title: "They report back",
    body: "They return with the verdict — exactly what you scored, before you even sit the paper.",
    alt: "A time traveller revealing a glowing prophecy of a grade to a delighted student.",
  },
];

export function HowItWorks() {
  return (
    <section className="space-y-6">
      <SectionHeading icon={Wand2} title="How it works" />
      <ol className="grid gap-6 sm:grid-cols-3">
        {STEPS.map((step, i) => (
          <li key={step.title} className="flex flex-col gap-4">
            <div className="relative aspect-square overflow-hidden rounded-xl border bg-muted">
              <Image
                src={step.img}
                alt={step.alt}
                fill
                sizes="(min-width: 640px) 33vw, 100vw"
                className="object-cover"
                // Pre-sized, pre-compressed static art (~66 KB webp), so:
                //  - `unoptimized`: skip the runtime image optimizer. Without
                //    `sharp` it falls back to a slow, memory-heavy OS pipeline.
                //  - NO `placeholder="blur"`: the bundler generates the blur
                //    placeholder at compile time via that same sharp-less
                //    pipeline, which livelocked next-swc (runaway CPU + memory).
                unoptimized
              />
              <span className="absolute left-3 top-3 inline-flex size-8 items-center justify-center rounded-full bg-primary text-sm font-semibold text-primary-foreground shadow">
                {i + 1}
              </span>
            </div>
            <div className="space-y-1">
              <h3 className="font-semibold">{step.title}</h3>
              <p className="text-sm text-muted-foreground">{step.body}</p>
            </div>
          </li>
        ))}
      </ol>
    </section>
  );
}
