import Image from "next/image";
import Link from "next/link";
import type { Metadata } from "next";
import { posts, formatPostDate } from "./posts";

export const metadata: Metadata = {
  title: "Blog - Scowld",
  description:
    "Guides and notes on Scowld, the free open-source iOS AI voice companion with camera vision, hands-free wake, and bring-your-own-key AI, speech-to-text, and text-to-speech.",
  alternates: { canonical: "/blog" },
  openGraph: {
    title: "Scowld Blog",
    description:
      "Guides on the Scowld AI voice companion: camera vision, bring-your-own-key providers, hands-free wake, and more.",
    url: "/blog",
    type: "website",
    images: [{ url: "/og-image-scowld.jpg", alt: "Scowld AI voice companion for iOS" }],
  },
};

export default function Blog() {
  const sorted = [...posts].sort((a, b) => b.datePublished.localeCompare(a.datePublished));

  const blogLd = {
    "@context": "https://schema.org",
    "@type": "Blog",
    name: "Scowld Blog",
    url: "https://www.scowld.xyz/blog",
    description:
      "Guides and notes on Scowld, the free open-source iOS AI voice companion.",
    blogPost: sorted.map((post) => ({
      "@type": "BlogPosting",
      headline: post.title,
      description: post.description,
      datePublished: post.datePublished,
      dateModified: post.dateModified,
      url: `https://www.scowld.xyz/blog/${post.slug}`,
      author: { "@type": "Person", name: "Apoorv Darshan" },
    })),
  };

  const breadcrumbLd = {
    "@context": "https://schema.org",
    "@type": "BreadcrumbList",
    itemListElement: [
      { "@type": "ListItem", position: 1, name: "Home", item: "https://www.scowld.xyz" },
      { "@type": "ListItem", position: 2, name: "Blog", item: "https://www.scowld.xyz/blog" },
    ],
  };

  return (
    <div className="legal">
      <nav className="legal__nav">
        <Link href="/" className="legal__nav-logo">
          <Image src="/logo.png" alt="Scowld" width={20} height={20} className="legal__nav-logo-img" />
          SCOWLD
        </Link>
      </nav>

      <div className="legal__container">
        <Link href="/" className="legal__back">&larr; Back to home</Link>
        <h1 className="legal__title">Scowld Blog</h1>
        <p className="legal__date">Guides on the AI voice companion</p>

        <div className="blog__list">
          {sorted.map((post) => (
            <Link key={post.slug} href={`/blog/${post.slug}`} className="post-card">
              <span className="post-card__meta">
                {formatPostDate(post.datePublished)} &middot; {post.readMinutes} min read
              </span>
              <h2 className="post-card__title">{post.title}</h2>
              <p className="post-card__excerpt">{post.excerpt}</p>
              <span className="post-card__more">Read more &rarr;</span>
            </Link>
          ))}
        </div>
      </div>

      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(blogLd) }} />
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(breadcrumbLd) }} />
    </div>
  );
}
