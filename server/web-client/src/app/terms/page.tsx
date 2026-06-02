'use client';

/**
 * Terms of Service Page
 *
 * DRAFT placeholder. Binding terms of service language requires legal authoring
 * and sign-off and has intentionally not been invented here. This page exists so
 * the registration and login links resolve, and states current beta facts only.
 */

import * as React from 'react';
import { useRouter } from 'next/navigation';
import { ArrowLeft } from 'lucide-react';
import { Button } from '@/components/ui';

export default function TermsPage() {
  const router = useRouter();

  return (
    <main className="min-h-screen">
      {/* Header */}
      <div className="flex items-center gap-2 px-4 py-3 border-b">
        <Button variant="ghost" size="icon" onClick={() => router.back()}>
          <ArrowLeft className="h-4 w-4" />
        </Button>
        <h1 className="text-lg font-semibold">Terms of Service</h1>
      </div>

      {/* Content */}
      <div className="container mx-auto px-4 py-6 max-w-2xl space-y-6 text-sm leading-relaxed">
        <div className="rounded-md border border-yellow-500/40 bg-yellow-500/10 p-4">
          <p className="font-medium">Draft, pending legal review</p>
          <p className="text-muted-foreground">
            These terms are a placeholder for the beta. Binding terms of service
            have not yet been finalized. By using the beta you accept the factual
            conditions below; full legal terms will be published before general
            availability.
          </p>
        </div>

        <section className="space-y-2">
          <h2 className="text-base font-semibold">Beta software</h2>
          <p>
            UnaMentis is provided as a beta for evaluation. Features may change or
            break, and availability is not guaranteed. Do not rely on it for
            critical needs.
          </p>
        </section>

        <section className="space-y-2">
          <h2 className="text-base font-semibold">Eligibility</h2>
          <p>
            You must be at least 13 years old to use UnaMentis. By registering you
            attest that you meet this requirement.
          </p>
        </section>

        <section className="space-y-2">
          <h2 className="text-base font-semibold">Acceptable use</h2>
          <p>
            Use UnaMentis lawfully and do not attempt to disrupt, abuse, or gain
            unauthorized access to the service or to other accounts.
          </p>
        </section>

        <section className="space-y-2">
          <h2 className="text-base font-semibold">Data</h2>
          <p>
            Your use is also governed by our{' '}
            <a href="/privacy" className="text-primary hover:underline">
              Privacy Policy
            </a>
            .
          </p>
        </section>

        <section className="space-y-2">
          <h2 className="text-base font-semibold">Pending sections</h2>
          <p className="text-muted-foreground">
            Liability, warranty disclaimers, governing law, dispute resolution,
            and account termination terms are pending legal authoring and are
            intentionally omitted from this draft.
          </p>
        </section>
      </div>
    </main>
  );
}
