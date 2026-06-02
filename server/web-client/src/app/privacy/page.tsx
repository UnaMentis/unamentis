'use client';

/**
 * Privacy Policy Page
 *
 * Factual description of current beta data practices. This reflects what the
 * code does today and is pending legal review before general availability.
 */

import * as React from 'react';
import { useRouter } from 'next/navigation';
import { ArrowLeft } from 'lucide-react';
import { Button } from '@/components/ui';

export default function PrivacyPage() {
  const router = useRouter();

  return (
    <main className="min-h-screen">
      {/* Header */}
      <div className="flex items-center gap-2 px-4 py-3 border-b">
        <Button variant="ghost" size="icon" onClick={() => router.back()}>
          <ArrowLeft className="h-4 w-4" />
        </Button>
        <h1 className="text-lg font-semibold">Privacy Policy</h1>
      </div>

      {/* Content */}
      <div className="container mx-auto px-4 py-6 max-w-2xl space-y-6 text-sm leading-relaxed">
        <p className="text-muted-foreground">
          Beta draft, last updated 2026-05-31. This describes our current data
          practices and is pending legal review. UnaMentis is for users 13 and
          older.
        </p>

        <section className="space-y-2">
          <h2 className="text-base font-semibold">What we collect</h2>
          <ul className="list-disc pl-5 space-y-1">
            <li>
              <strong>Account data:</strong> your email, a securely hashed
              password, basic device information (a device fingerprint and the
              app/browser user agent), used to create and secure your account.
            </li>
            <li>
              <strong>Aggregate session telemetry:</strong> non-content metrics
              such as session length, turn and interruption counts, latency,
              estimated costs, and thermal/network events. This is keyed to a
              per-install random identifier and contains no transcripts or
              learning content.
            </li>
            <li>
              <strong>Network address:</strong> on telemetry and log intake we
              coarsen your IP address before storing it (IPv4 to a /24 network,
              IPv6 to a /48). We do not store your exact IP from these endpoints.
            </li>
          </ul>
        </section>

        <section className="space-y-2">
          <h2 className="text-base font-semibold">Voice and transcripts</h2>
          <p>
            UnaMentis servers do not store voice recordings or transcripts. When
            you use a cloud voice provider, your audio and transcripts are sent
            to a third-party AI provider to produce responses. Their handling and
            retention are governed by that provider. If you select on-device
            providers, audio stays on your device.
          </p>
        </section>

        <section className="space-y-2">
          <h2 className="text-base font-semibold">Third-party AI providers</h2>
          <p>
            We use external services to provide parts of the product. See our{' '}
            <a
              href="https://github.com/UnaMentis/unamentis/blob/main/docs/SUBPROCESSORS.md"
              className="text-primary hover:underline"
              target="_blank"
              rel="noopener noreferrer"
            >
              Sub-Processor List
            </a>{' '}
            for the current set and what data each receives.
          </p>
        </section>

        <section className="space-y-2">
          <h2 className="text-base font-semibold">Children</h2>
          <p>
            UnaMentis is intended for users 13 and older. Registration requires a
            self-attestation that you are at least 13. We do not knowingly collect
            data from children under 13. Verifiable parental consent flows are not
            offered in the beta.
          </p>
        </section>

        <section className="space-y-2">
          <h2 className="text-base font-semibold">Your choices</h2>
          <p>
            We aim to minimize the data we store. Automated self-service export
            and deletion are not yet available in the beta; to request export or
            deletion of your account data, contact support. Enforced retention
            schedules and an in-app privacy dashboard are planned and not yet
            implemented.
          </p>
        </section>

        <section className="space-y-2">
          <h2 className="text-base font-semibold">Contact</h2>
          <p>
            Questions about privacy: contact support through the channel provided
            with your beta invitation.
          </p>
        </section>
      </div>
    </main>
  );
}
