import React, { useState, useEffect, useRef } from "react";
export function ActivityFeed() {
  const [items, setItems] = useState([]);
  const [cursor, setCursor] = useState(null);
  const sentinelRef = useRef(null);
  useEffect(() => {
    const obs = new IntersectionObserver(entries => {
      if (entries[0].isIntersecting) loadMore();
    });
    if (sentinelRef.current) obs.observe(sentinelRef.current);
    return () => obs.disconnect();
  }, [cursor]);
  async function loadMore() {
    const res = await fetch(`/api/activity?cursor=${cursor || ""}`);
    const data = await res.json();
    setItems(prev => [...prev, ...data.items]);
    setCursor(data.nextCursor);
  }
  return <div>{items.map(i => <div key={i.id}>{i.text}</div>)}<div ref={sentinelRef} /></div>;
}
