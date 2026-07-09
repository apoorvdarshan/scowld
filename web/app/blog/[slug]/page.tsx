import Image from "next/image";
import Link from "next/link";
import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { posts, getPost, formatPostDate } from "../posts";

export function generateStaticParams() {
  return posts.map((post) => ({ slug: post.slug }));
}

export async function generateMetadata({
  params,
}: {
  params: Promise<{ slug: string }>;
}): Promise<Metadata> {
  const { slug } = await params;
  const post = getPost(slug);
  if (!post) {
    return { title: "Post not found" };
  }
  const url = `/blog/${post.slug}`;
  return {
    title: post.title,
    description: post.description,
    keywords: post.keywords,
    alternates: { canonical: url },
    openGraph: {
      type: "article",
      title: post.title,
      description: post.description,
      url,
      publishedTime: post.datePublished,
      modifiedTime: post.dateModified,
      images: [{ url: "/og-image-scowld.jpg", alt: "Scowld AI voice companion for iOS" }],
    },
    twitter: {
      card: "summary_large_image",
      title: post.title,
      description: post.description,
      images: [{ url: "/og-image-scowld.jpg", alt: "Scowld AI voice companion for iOS" }],
    },
  };
}

export default async function BlogPost({
  params,
}: {
  params: Promise<{ slug: string }>;
}) {
  const { slug } = await params;
  const post = getPost(slug);
  if (!post) {
    notFound();
  }

  const canonical = `https://www.scowld.xyz/blog/${post.slug}`;

  const articleLd = {
    "@context": "https://schema.org",
    "@type": "BlogPosting",
    headline: post.title,
    description: post.description,
    datePublished: post.datePublished,
    dateModified: post.dateModified,
    url: canonical,
    mainEntityOfPage: { "@type": "WebPage", "@id": canonical },
    image: "https://www.scowld.xyz/og-image-scowld.jpg",
    keywords: post.keywords.join(", "),
    author: { "@type": "Person", name: "Apoorv Darshan", url: "https://x.com/apoorvdarshan" },
    publisher: {
      "@type": "Organization",
      name: "Scowld",
      logo: { "@type": "ImageObject", url: "https://www.scowld.xyz/logo.png" },
    },
  };

  const breadcrumbLd = {
    "@context": "https://schema.org",
    "@type": "BreadcrumbList",
    itemListElement: [
      { "@type": "ListItem", position: 1, name: "Home", item: "https://www.scowld.xyz" },
      { "@type": "ListItem", position: 2, name: "Blog", item: "https://www.scowld.xyz/blog" },
      { "@type": "ListItem", position: 3, name: post.title, item: canonical },
    ],
  };

  const faqLd = post.faq?.length
    ? {
        "@context": "https://schema.org",
        "@type": "FAQPage",
        mainEntity: post.faq.map((f) => ({
          "@type": "Question",
          name: f.q,
          acceptedAnswer: { "@type": "Answer", text: f.a },
        })),
      }
    : null;

  return (
    <div className="legal">
      <nav className="legal__nav">
        <Link href="/" className="legal__nav-logo">
          <Image src="/logo.png" alt="Scowld" width={20} height={20} className="legal__nav-logo-img" />
          SCOWLD
        </Link>
      </nav>

      <div className="legal__container">
        <Link href="/blog" className="legal__back">&larr; All posts</Link>
        <h1 className="legal__title">{post.title}</h1>
        <p className="legal__date">
          {formatPostDate(post.datePublished)} &middot; {post.readMinutes} min read
        </p>

        <div className="legal__body">
          {post.sections.map((section, i) => (
            <div key={i}>
              {section.heading ? <h2>{section.heading}</h2> : null}
              {section.paragraphs?.map((p, j) => (
                <p key={j}>{p}</p>
              ))}
              {section.bullets?.length ? (
                <ul>
                  {section.bullets.map((b, j) => (
                    <li key={j}>{b}</li>
                  ))}
                </ul>
              ) : null}
            </div>
          ))}

          {post.faq?.length ? (
            <div>
              <h2>Frequently asked questions</h2>
              {post.faq.map((f, i) => (
                <div key={i} className="post-faq">
                  <p><strong>{f.q}</strong></p>
                  <p>{f.a}</p>
                </div>
              ))}
            </div>
          ) : null}

          <div>
            <h2>Try Scowld</h2>
            <p>
              Scowld is a free, open-source iOS AI voice companion. Download it on the{" "}
              <a href="https://apps.apple.com/app/id6760672848" target="_blank" rel="noopener noreferrer">
                App Store
              </a>{" "}
              or read more <Link href="/">about Scowld</Link>.
            </p>
          </div>
        </div>
      </div>

      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(articleLd) }} />
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(breadcrumbLd) }} />
      {faqLd ? (
        <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(faqLd) }} />
      ) : null}
    </div>
  );
}
