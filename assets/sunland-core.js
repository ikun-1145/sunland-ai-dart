var jn = Object.defineProperty;
var yn = (e, t, n) => t in e ? jn(e, t, { enumerable: !0, configurable: !0, writable: !0, value: n }) : e[t] = n;
var _ = (e, t, n) => yn(e, typeof t != "symbol" ? t + "" : t, n);
const p = {
  /** Inheritance / subclass-of, e.g. 猫 属于 哺乳动物 */
  IsA: "属于",
  /** Identity / instance-of, e.g. 苏格拉底 是 人 */
  Is: "是",
  /** Capability, e.g. 鸟 会 飞 */
  Can: "会",
  /** Preference, e.g. 猫 喜欢 鱼 */
  Likes: "喜欢",
  /** Spatial location, e.g. 猫 在 屋顶 */
  LocatedIn: "在"
}, ie = {
  Name: "name"
};
let bt = 0;
function On() {
  return bt += 1, `k_${Date.now().toString(36)}_${bt.toString(36)}`;
}
const En = 1, Sn = "user";
function me(e) {
  return `${e.subject} ${e.relation} ${e.object} ${e.negated}`;
}
function Ae(e, t, n) {
  const r = e.get(t);
  r === void 0 ? e.set(t, /* @__PURE__ */ new Set([n])) : r.add(n);
}
function xe(e, t, n) {
  const r = e.get(t);
  r !== void 0 && (r.delete(n), r.size === 0 && e.delete(t));
}
function wn(e) {
  const t = [...e].sort((c, s) => c.size - s.size), [n, ...r] = t;
  if (n === void 0) return /* @__PURE__ */ new Set();
  let i = n;
  for (const c of r) {
    const s = /* @__PURE__ */ new Set();
    for (const a of i)
      c.has(a) && s.add(a);
    if (i = s, i.size === 0) break;
  }
  return i;
}
function Cn(e, t) {
  return !(t.subject !== void 0 && e.subject !== t.subject || t.relation !== void 0 && e.relation !== t.relation || t.object !== void 0 && e.object !== t.object || t.negated !== void 0 && e.negated !== t.negated);
}
function Rn(e) {
  if (Number.isNaN(e) || e < 0 || e > 1)
    throw new RangeError(`confidence must be within [0, 1], got ${e}`);
}
class xt {
  constructor() {
    _(this, "records", /* @__PURE__ */ new Map());
    _(this, "bySubject", /* @__PURE__ */ new Map());
    _(this, "byRelation", /* @__PURE__ */ new Map());
    _(this, "byObject", /* @__PURE__ */ new Map());
    _(this, "idByTripleKey", /* @__PURE__ */ new Map());
  }
  all() {
    return Array.from(this.records.values());
  }
  has(t) {
    return this.idByTripleKey.has(me(t));
  }
  match(t) {
    const n = [];
    t.subject !== void 0 && n.push(this.bySubject.get(t.subject) ?? /* @__PURE__ */ new Set()), t.relation !== void 0 && n.push(this.byRelation.get(t.relation) ?? /* @__PURE__ */ new Set()), t.object !== void 0 && n.push(this.byObject.get(t.object) ?? /* @__PURE__ */ new Set());
    const r = n.length > 0 ? wn(n) : this.records.keys(), i = [];
    for (const c of r) {
      const s = this.records.get(c);
      s !== void 0 && Cn(s, t) && i.push(s);
    }
    return i;
  }
  add(t, n) {
    const r = this.idByTripleKey.get(me(t));
    if (r !== void 0) {
      const s = this.records.get(r);
      if (s !== void 0) return s;
    }
    const i = (n == null ? void 0 : n.confidence) ?? En;
    Rn(i);
    const c = {
      subject: t.subject,
      relation: t.relation,
      object: t.object,
      negated: t.negated,
      id: On(),
      confidence: i,
      source: (n == null ? void 0 : n.source) ?? Sn,
      createdAt: (/* @__PURE__ */ new Date()).toISOString()
    };
    return this.insertRecord(c), c;
  }
  addMany(t) {
    for (const n of t)
      this.records.has(n.id) || this.insertRecord(n);
  }
  remove(t) {
    const n = this.records.get(t);
    n !== void 0 && (this.records.delete(t), this.idByTripleKey.delete(me(n)), xe(this.bySubject, n.subject, t), xe(this.byRelation, n.relation, t), xe(this.byObject, n.object, t));
  }
  clear() {
    this.records.clear(), this.bySubject.clear(), this.byRelation.clear(), this.byObject.clear(), this.idByTripleKey.clear();
  }
  insertRecord(t) {
    this.records.set(t.id, t), this.idByTripleKey.set(me(t), t.id), Ae(this.bySubject, t.subject, t.id), Ae(this.byRelation, t.relation, t.id), Ae(this.byObject, t.object, t.id);
  }
}
const kn = [
  { subject: "猫", relation: p.IsA, object: "哺乳动物", negated: !1 },
  { subject: "哺乳动物", relation: p.IsA, object: "动物", negated: !1 },
  { subject: "苏格拉底", relation: p.Is, object: "人", negated: !1 },
  { subject: "人", relation: p.IsA, object: "动物", negated: !1 },
  { subject: "鸟", relation: p.Can, object: "飞", negated: !1 },
  { subject: "企鹅", relation: p.IsA, object: "鸟", negated: !1 },
  { subject: "企鹅", relation: p.Can, object: "飞", negated: !0 },
  { subject: "猫", relation: p.Likes, object: "鱼", negated: !1 },
  { subject: "猫", relation: p.LocatedIn, object: "屋顶", negated: !1 }
];
function zn(e) {
  for (const t of kn)
    e.add(t, { source: "seed" });
}
function In(e, t, n) {
  t.setItem(n, JSON.stringify(e.all()));
}
function Nn(e, t, n) {
  const r = t.getItem(n);
  if (r === null) return;
  let i;
  try {
    i = JSON.parse(r);
  } catch {
    return;
  }
  Array.isArray(i) && e.addMany(i);
}
const Q = "Sunland AI · Beta", Tn = "霜蓝", Lt = "开发者", vn = [
  {
    subject: Q,
    relation: p.Is,
    object: "一个基于符号推理与知识图谱的AI系统：不依赖大语言模型，而是用显式的知识（事实）和推理规则来理解、学习与回答问题",
    negated: !1
  },
  {
    subject: Tn,
    relation: p.Is,
    object: "Sunland AI · Beta 目前的默认人格，说话自然温和、带一点点俏皮，仅负责语气，不改变任何事实或推理结论",
    negated: !1
  },
  {
    subject: Q,
    relation: p.Can,
    object: "记住你教给它的知识（比如「猫属于哺乳动物」），并在之后的对话里用上",
    negated: !1
  },
  {
    subject: Q,
    relation: p.Can,
    object: "基于已知事实做推理、回答问题，并且能解释自己是怎么得出这个答案的",
    negated: !1
  },
  {
    subject: Q,
    relation: Lt,
    object: "由一名独立开发者持续设计与打磨，目前仍在成长中",
    negated: !1
  }
];
function An() {
  const e = new xt();
  for (const t of vn)
    e.add(t, { source: "seed" });
  return e;
}
function xn() {
  return new xt();
}
let gt = 0;
function Ln() {
  return gt += 1, `mem_${Date.now().toString(36)}_${gt.toString(36)}`;
}
class $n {
  constructor() {
    _(this, "records", /* @__PURE__ */ new Map());
  }
  remember(t, n) {
    const r = (/* @__PURE__ */ new Date()).toISOString(), i = this.records.get(t), c = i ? { ...i, value: n, updatedAt: r } : { id: Ln(), key: t, value: n, createdAt: r, updatedAt: r };
    return this.records.set(t, c), c;
  }
  recall(t) {
    return this.records.get(t) ?? null;
  }
  forget(t) {
    this.records.delete(t);
  }
  list() {
    return Array.from(this.records.values());
  }
  search(t) {
    const n = t.toLowerCase();
    return this.list().filter(
      (r) => r.key.toLowerCase().includes(n) || r.value.toLowerCase().includes(n)
    );
  }
  restore(t) {
    for (const n of t)
      this.records.has(n.key) || this.records.set(n.key, n);
  }
}
function _n(e, t, n) {
  t.setItem(n, JSON.stringify(e.list()));
}
function Kn(e, t, n) {
  const r = t.getItem(n);
  if (r === null) return;
  let i;
  try {
    i = JSON.parse(r);
  } catch {
    return;
  }
  Array.isArray(i) && e.restore(i);
}
function Mn() {
  return new $n();
}
const Pn = /\s+/gu, Dn = /[呀啊呢哦啦~～]+$/u;
function ht(e) {
  return e.replace(Pn, "").replace(Dn, "").toLowerCase();
}
function Se(e, t, n = 0.95) {
  const r = new Set(t.map(ht));
  return {
    intent: e,
    match(i) {
      return r.has(ht(i)) ? { entities: [], confidence: n } : null;
    }
  };
}
const Un = [
  "你好",
  "您好",
  "哈喽",
  "哈啰",
  "嗨",
  "hi",
  "hello",
  "hey"
];
function qn() {
  return Se("Greeting", Un);
}
const Bn = [
  "谢谢",
  "谢了",
  "感谢",
  "多谢",
  "thanks",
  "thank you",
  "thx"
];
function Fn() {
  return Se("Thanks", Bn);
}
const Wn = [
  "再见",
  "拜拜",
  "88",
  "bye",
  "goodbye",
  "see you"
];
function Vn() {
  return Se("Farewell", Wn);
}
const pt = "Sunland AI · Beta", Gn = "霜蓝";
function Yn(e) {
  return e.includes("霜蓝") || e.includes("frost") ? Gn : e.includes("sunland") || e.includes("你") ? pt : null;
}
const Qn = ["谁开发", "谁做的", "谁创造", "谁写的", "开发者"], Hn = ["能做什么", "会做什么", "能干什么", "能做啥", "会做啥", "能干嘛", "有什么能力", "擅长什么"], Jn = ["是谁", "叫什么", "是什么", "你的名字", "名字是"];
function Xn(e) {
  return Qn.some((t) => e.includes(t)) ? "creator" : Hn.some((t) => e.includes(t)) ? "capability" : Jn.some((t) => e.includes(t)) ? "identity" : null;
}
function Zn() {
  return {
    intent: "Identity",
    match(e) {
      const t = e.toLowerCase(), n = Yn(t), r = Xn(t);
      return n === null || r === null ? null : { entities: [n, r], confidence: 0.9 };
    }
  };
}
const er = [
  "我叫什么",
  "我叫什么名字",
  "你知道我的名字吗",
  "你记得我叫什么吗",
  "你记得我的名字吗",
  "你还记得我的名字吗",
  "还记得我是谁吗"
];
function tr() {
  return Se("RecallName", er);
}
const qe = Object.freeze({
  maxInputLength: 160,
  maxNameLength: 64,
  maxRelationMentions: 1
}), nr = /[,，;；。.!！?？\r\n]/u, rr = /[。.!！]+$/u, ir = /[?？]|(?:是不是|会不会|有没有|能不能|属不属于|为什么|怎么|什么|啥|谁|哪里|哪儿|吗|呢)(?:[啊呀呢哦啦]?[。.!！]?)$/u, cr = /(?:还是|或者|或是|然后|并且|而且|同时|接着|另外)/u, sr = /(?:不要|别|无需|不用|禁止)(?:再)?(?:记住|记|保存|学习|教)/u, ar = Object.freeze([
  "指的是",
  "意思是",
  "是一种",
  "属于",
  "喜欢",
  "拥有",
  "具备",
  "会",
  "有",
  "是",
  "在"
]);
function $t(e) {
  return e.trim().replace(rr, "").trim();
}
function or(e) {
  return nr.test(
    $t(e)
  );
}
function ur(e) {
  return ir.test(e.trim());
}
function _t(e) {
  return cr.test(e);
}
function Kt(e) {
  return sr.test(e);
}
function Mt(e) {
  let t = e, n = 0;
  for (const r of ar) {
    let i = t.indexOf(r);
    for (; i >= 0; )
      n += 1, t = t.slice(0, i) + " ".repeat(r.length) + t.slice(i + r.length), i = t.indexOf(r);
  }
  return n;
}
function tt(e) {
  const t = e.trim();
  return t.length === 0 || t.length > qe.maxInputLength || or(t) || ur(t) || _t(t) || Kt(t) || Mt(t) > qe.maxRelationMentions;
}
function Be(e) {
  return $t(e).replace(/\s+/gu, " ").trim();
}
const lr = [
  /^我\s*叫\s*(.+)$/iu,
  /^我的名字\s*是\s*(.+)$/iu,
  /^你可以\s*叫我\s*(.+)$/iu,
  /^叫我\s*(.+)$/iu
], fr = /* @__PURE__ */ new Set(["什么", "什么名字", "谁"]), dr = /^(?:你好|您好|嗨|哈喽|hello|hi)[,，]\s*/iu, mr = /[呀啊呢哦啦吧~～]+$/u, br = /^[\p{P}\p{S}\s]+$/u;
function gr(e) {
  const t = e.trim().replace(dr, "");
  if (tt(t))
    return null;
  for (const n of lr) {
    const r = n.exec(t);
    if (!r) continue;
    const i = Be(r[1] ?? "").replace(mr, "").trim();
    return i.length === 0 || i.length > qe.maxNameLength || fr.has(i) || br.test(i) || _t(i) || Mt(i) > 0 ? null : i;
  }
  return null;
}
function hr() {
  return {
    intent: "RememberName",
    match(e, t) {
      const n = gr(t ?? e);
      return n === null ? null : { entities: [n], confidence: 0.95 };
    }
  };
}
const pr = [
  qn(),
  Fn(),
  Vn(),
  tr(),
  Zn(),
  hr()
], jr = /\s+/gu, yr = /[?？!！。.,，;；]+$/u;
function Or(e) {
  return e.replace(jr, "").replace(yr, "");
}
function we(e) {
  return e.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}
function Er(e) {
  return [...e].map((t) => we(t)).join("\\s*");
}
function Fe(e, t = [e]) {
  const n = [...t].sort((i, c) => c.length - i.length).map(Er).join("|"), r = new RegExp(
    `^\\s*(.+?)\\s*(不|没)?\\s*(?:${n})\\s*(.+?)\\s*[。.!！]*\\s*$`,
    "u"
  );
  return {
    name: `statement:${e}`,
    match(i, c) {
      const s = c ?? i;
      if (tt(s))
        return null;
      const a = r.exec(s);
      if (!a) return null;
      const [, o, d, l] = a;
      if (!o || !l) return null;
      const b = Be(o), g = Be(l);
      return !b || !g ? null : {
        type: "statement",
        subject: b,
        relation: e,
        object: g,
        negated: d === "不" || d === "没",
        raw: s
      };
    }
  };
}
function Sr(e) {
  const t = we(e), n = new RegExp(`^(.+?)${t}什么$`, "u");
  return {
    name: `query:object-of:${e}`,
    match(r) {
      const i = n.exec(r);
      if (!i) return null;
      const [, c] = i;
      return c ? {
        type: "query",
        subject: c,
        relation: e,
        kind: "object-of",
        raw: r
      } : null;
    }
  };
}
function wr(e) {
  return `${e.charAt(0)}不${e}`;
}
function Cr(e) {
  const t = wr(e), n = we(t), r = new RegExp(`^(.+?)${n}(.+)$`, "u");
  return {
    name: `query:verify:${e}`,
    match(i) {
      const c = r.exec(i);
      if (!c) return null;
      const [, s, a] = c;
      return !s || !a ? null : {
        type: "query",
        subject: s,
        relation: e,
        object: a,
        kind: "verify",
        raw: i
      };
    }
  };
}
const Rr = /^(.+?)在哪里$/u;
function kr() {
  return {
    name: "query:locate",
    match(e) {
      const t = Rr.exec(e);
      if (!t) return null;
      const [, n] = t;
      return n ? {
        type: "query",
        subject: n,
        relation: p.LocatedIn,
        kind: "locate",
        raw: e
      } : null;
    }
  };
}
function zr(e) {
  const t = we(e), n = new RegExp(`^(.+?)为什么${t}(.+)$`, "u");
  return {
    name: `query:why:${e}`,
    match(r) {
      const i = n.exec(r);
      if (!i) return null;
      const [, c, s] = i;
      return !c || !s ? null : {
        type: "query",
        subject: c,
        relation: e,
        object: s,
        kind: "verify",
        explain: !0,
        raw: r
      };
    }
  };
}
const be = [
  p.IsA,
  p.Is,
  p.Can,
  p.Likes,
  p.LocatedIn
], Ir = [
  Fe("意思是", ["指的是", "意思是"]),
  Fe("有")
], Nr = [
  kr(),
  ...be.map(zr),
  ...be.map(Cr),
  ...be.map(Sr),
  ...Ir,
  ...be.map(
    (e) => Fe(e)
  )
];
class Tr {
  constructor(t = Nr, n = pr) {
    _(this, "patterns");
    _(this, "intentMatchers");
    this.patterns = t, this.intentMatchers = n;
  }
  parse(t) {
    const n = Or(t);
    if (!n)
      return { type: "unknown", raw: t, reason: "输入为空" };
    for (const r of this.intentMatchers) {
      const i = r.match(n, t);
      if (i)
        return {
          type: "intent",
          intent: r.intent,
          entities: i.entities ?? [],
          confidence: i.confidence,
          raw: t
        };
    }
    for (const r of this.patterns) {
      const i = r.match(n, t);
      if (i)
        return { ...i, raw: t };
    }
    return {
      type: "unknown",
      raw: t,
      reason: `没有匹配的语法规则："${n}"`
    };
  }
}
function Pt() {
  return new Tr();
}
function K(...e) {
  return e.filter((t) => !!(t && t.length > 0)).join(" ");
}
function vr(e) {
  let t = 0;
  for (let n = 0; n < e.length; n += 1)
    t = t * 31 + e.charCodeAt(n) | 0;
  return Math.abs(t);
}
function E(e, t) {
  if (e.length === 0)
    throw new Error("pickBySeed: `items` must not be empty");
  const n = vr(t) % e.length;
  return e[n];
}
const Ar = ["✨", "🌸", "🐾", "💙"], xr = [
  "让我查一下知识图谱。",
  "嗯，这个我知道。",
  "好，我来说说。",
  "这个问题我有答案。"
], Lr = [
  "如果还有其他想问的，随时说。",
  "还想了解更多的话，尽管问我。",
  "这就是我推理出来的结论。",
  "如果这跟你在琢磨兽设或者创作有关，我也挺好奇后续的。"
  // furry nod
], $r = [
  "唔，这个我目前还没有相关的知识。",
  "抱歉，我暂时还不知道这个。",
  "这个我还没学过。"
], _r = [
  "如果你知道答案，可以教教我，我会把它记下来。",
  "要是愿意告诉我，我会记住的，下次就能直接回答。",
  "随时欢迎补充知识给我，多多益善。"
], Kr = [
  "不过这个我不是很有把握，仅供参考～",
  "这个我没有十足的信心，你可以再和我确认一下～",
  "这只是我的推测，不一定完全准确～"
], Mr = [
  "好，我记下来了：",
  "明白了，这条知识我存起来了：",
  "收到，这条我记住了："
], Pr = [
  "以后可以直接问我这个。",
  "下次遇到相关问题，我就能用上它了。",
  "谢谢你教我新知识。"
], Dr = [
  "这个问题我暂时还没理解清楚。",
  "唔，我暂时还没弄明白你想问什么。"
], Ur = [
  "你可以换一种说法，或者再告诉我一点相关信息。",
  "可以再多说一点，或者换个方式告诉我。"
], qr = [
  "你好呀～有什么想聊的，或者想教我点新知识吗？",
  "嗨，我在这里，想问点什么都可以。",
  "欢迎回来～需要我帮忙推理点什么吗？",
  "嗨，无论是新知识还是兽设点子，我都很乐意听听。"
  // furry nod
], Br = [
  "不客气～能帮上忙我也很开心。",
  "不用谢，这是我应该做的。",
  "嘿嘿，随时欢迎再来问我。",
  "能帮到你就好，有别的问题也尽管说。"
], Fr = [
  "拜拜～下次再聊！",
  "再见，期待下次和你聊天。",
  "先这样啦，有需要随时回来找我。",
  "路上小心～我在这里等你回来。"
], Wr = [
  "关于我是谁，",
  "让我介绍一下自己：",
  "问得好，"
], Vr = [
  "如果还想了解更多，随时问我。",
  "有什么想知道的都可以接着问～"
], Gr = [
  "我目前能做的事情大概有这些：",
  "说说看我能帮上什么忙："
], Yr = [
  "随着你教给我更多知识，我会越来越强。",
  "以后应该还会有更多能力，敬请期待～"
], Qr = [
  "说到这个呀，",
  "关于这个问题，"
], Hr = [
  "希望我能越来越好用。",
  "也谢谢你愿意花时间和我聊天～"
], Jr = [
  "好呀，",
  "记住啦，",
  "收到～"
], Xr = [
  "以后见面我都会记得你。",
  "很高兴认识你！",
  "下次再聊我就认得你啦。"
], Zr = [
  "你叫",
  "我记得，你是",
  "当然记得呀，你是"
], ei = [
  "，对吧？",
  "呀！",
  "，很高兴又和你聊天。"
], ti = [
  "目前你还没有告诉我你的名字。",
  "我还不知道你的名字诶，要不要告诉我？"
], ni = [
  "好，我记住了：",
  "收到，这个我记下了："
], ri = [
  "以后我都会记得。",
  "谢谢你告诉我～"
], ii = [
  "这个你还没有告诉过我。",
  "唔，这个我暂时还不知道。"
];
function O(e, t) {
  const n = E(Ar, t);
  return `${e} ${n}`;
}
function ci(e, t) {
  const n = `${e.query.subject}:${e.query.relation}:${e.query.kind}`, r = t.mode !== "no-answer", i = E(
    r ? xr : $r,
    n
  ), c = E(
    r ? Lr : _r,
    `${n}:closer`
  ), s = t.isUncertain ? E(Kr, `${n}:hedge`) : void 0;
  return O(K(i, t.explanation, s, c), n);
}
function si(e) {
  const t = `${e.subject}:${e.relation}:${e.object}`, n = E(Mr, t), r = E(Pr, `${t}:closer`), i = e.negated ? "不" : "", c = `${e.subject} ${i}${e.relation} ${e.object}`;
  return O(K(n, c, r), t);
}
function ai(e) {
  const t = e.raw.trim();
  if (!t)
    return O("好像还没有输入内容呢，可以跟我说点什么。", "empty-input");
  const n = t, r = E(Dr, n), i = E(Ur, `${n}:closer`);
  return O(K(r, i), n);
}
function oi(e) {
  const t = e && e.length > 0 ? e : "greeting", n = E(qr, t);
  return O(n, t);
}
function ui(e) {
  const t = e && e.length > 0 ? e : "thanks", n = E(Br, t);
  return O(n, t);
}
function li(e) {
  const t = e && e.length > 0 ? e : "farewell", n = E(Fr, t);
  return O(n, t);
}
function fi(e) {
  var r;
  const t = new Set(e.candidateLabels), n = [
    e.clarificationKind,
    e.focus,
    e.relation ?? "",
    ...e.candidateLabels
  ].join(":");
  if (t.has("identity") && t.has("query"))
    return O(
      "这个问题里像是同时问了我的名字和能力，可以分开问我哦。",
      n
    );
  if (e.focus === "subject" && (((r = e.contextLabels) == null ? void 0 : r.length) ?? 0) >= 2) {
    const i = e.contextLabels ?? [], c = [
      i.slice(0, -1).join("、"),
      i.at(-1)
    ].join("还是");
    return O(
      `你指的是${c}呢？可以再告诉我一下哦。`,
      n
    );
  }
  return e.focus === "object" && e.relation === "会" ? O("你想问我会做什么呢？可以再具体一点点哦。", n) : e.focus === "object" ? O(
    "这里好像还缺少要说明的内容，可以再告诉我它是什么吗？",
    n
  ) : e.focus === "subject" ? O("你想问的是谁或什么呢？可以再告诉我一点点。", n) : e.focus === "relation" ? O("你想了解它哪一方面呢？可以再说具体一点点。", n) : e.focus === "name" ? O("你是在问名字，还是想告诉我你的名字呢？", n) : t.has("teaching") ? O(
    "这个知识好像还没说完整，可以再告诉我对象和它们的关系吗？",
    n
  ) : O(
    "我好像看到了不止一种意思，可以换一种更具体的说法吗？",
    n
  );
}
function di(e, t, n, r) {
  const i = r && r.length > 0 ? r : `identity:${t}:${e}`;
  if (e === "capability") {
    const d = E(Gr, i), l = E(Yr, `${i}:closer`), b = n.length > 0 ? n.map((g) => `· ${g.object}`).join(`
`) : `关于「${t}」能做什么，我目前还没有明确的答案。`;
    return O(K(d, b, l), i);
  }
  if (e === "creator") {
    const d = E(Qr, i), l = E(Hr, `${i}:closer`), [b] = n, g = b ? b.object : "这个我暂时还不清楚。";
    return O(K(d, g, l), i);
  }
  const c = E(Wr, i), s = E(Vr, `${i}:closer`), [a] = n, o = a ? `${a.subject} ${a.negated ? "不" : ""}${a.relation} ${a.object}` : `关于「${t}」，我目前还没有明确的答案。`;
  return O(K(c, o, s), i);
}
function mi(e, t, n) {
  const r = n && n.length > 0 ? n : `remembered:${e}`;
  if (e === ie.Name) {
    const s = E(Jr, r), a = E(Xr, `${r}:closer`);
    return O(K(s, `你叫 ${t}`, a), r);
  }
  const i = E(ni, r), c = E(ri, `${r}:closer`);
  return O(K(i, t, c), r);
}
function bi(e, t, n) {
  const r = n && n.length > 0 ? n : `recalled:${e}`;
  if (e === ie.Name) {
    if (t === null)
      return O(E(ti, r), r);
    const i = E(Zr, r), c = E(ei, `${r}:closer`);
    return O(K(i, t, c), r);
  }
  return O(t === null ? E(ii, r) : t, r);
}
function gi(e) {
  return "抱歉，我现在遇到了一点问题，请稍后再试一次。";
}
const We = {
  id: "frost",
  displayName: "霜蓝 Frost",
  description: "温柔友善、带一点活力的兽圈朋友型人格。默认人格。仅影响语言风格与语气，不改变任何推理结论、置信度或知识内容。",
  respond(e) {
    switch (e.kind) {
      case "reasoning-result":
        return ci(e.result, e.plan);
      case "clarification":
        return fi(e.plan);
      case "learned":
        return si(e.record);
      case "unknown-input":
        return ai(e.failure);
      case "greeting":
        return oi(e.raw);
      case "thanks":
        return ui(e.raw);
      case "farewell":
        return li(e.raw);
      case "identity":
        return di(e.aspect, e.subject, e.facts, e.raw);
      case "remembered":
        return mi(e.key, e.value, e.raw);
      case "recalled":
        return bi(e.key, e.value, e.raw);
      case "error":
        return gi(e.message);
      default: {
        const t = e;
        throw new Error(`Frost: unhandled response context ${JSON.stringify(t)}`);
      }
    }
  }
}, jt = {
  id: "plain",
  displayName: "Plain（无风格 / 调试用）",
  description: "不做任何语言风格修饰的基线人格，仅用于验证人格切换机制与调试输出。",
  respond(e) {
    var t;
    switch (e.kind) {
      case "reasoning-result":
        return e.plan.isUncertain ? `${e.plan.explanation}（不确定）` : e.plan.explanation;
      case "clarification":
        if (e.plan.focus === "subject" && (((t = e.plan.contextLabels) == null ? void 0 : t.length) ?? 0) >= 2) {
          const n = e.plan.contextLabels ?? [];
          return `你指的是${[
            n.slice(0, -1).join("、"),
            n.at(-1)
          ].join("还是")}？请再说明一下。`;
        }
        return e.plan.focus === "object" && e.plan.relation === "会" ? "你想问会做什么？请再具体一点。" : e.plan.focus === "object" ? "缺少要说明的内容，请补充完整。" : e.plan.focus === "subject" ? "缺少要询问的对象，请补充完整。" : e.plan.focus === "relation" ? "缺少要询问的方面，请补充完整。" : e.plan.focus === "name" ? "请说明你是在询问名字，还是提供名字。" : "这句话有多种可能的意思，请换一种更具体的说法。";
      case "learned": {
        const n = e.record.negated ? "不" : "";
        return `已记录：${e.record.subject} ${n}${e.record.relation} ${e.record.object}`;
      }
      case "unknown-input":
        return e.failure.raw.trim() ? "这个问题我暂时还没理解清楚。你可以换一种说法，或者再告诉我一点相关信息。" : "好像还没有输入内容呢，可以跟我说点什么。";
      case "greeting":
        return "你好。";
      case "thanks":
        return "不客气。";
      case "farewell":
        return "再见。";
      case "identity": {
        const [n] = e.facts;
        if (!n) return `未知：关于 ${e.subject}（${e.aspect}）`;
        const r = n.negated ? "不" : "";
        return `${n.subject} ${r}${n.relation} ${n.object}`;
      }
      case "remembered":
        return `已记住：${e.key} = ${e.value}`;
      case "recalled":
        return e.value === null ? `未知：${e.key}` : `${e.key} = ${e.value}`;
      case "error":
        return "暂时无法完成这次请求，请稍后再试。";
      default: {
        const n = e;
        throw new Error(`Plain: unhandled response context ${JSON.stringify(n)}`);
      }
    }
  }
}, hi = We.id, ce = /* @__PURE__ */ new Map();
function pi() {
  ce.set(We.id, We), ce.set(jt.id, jt);
}
pi();
function Ra(e) {
  ce.set(e.id, e);
}
function ka() {
  return Array.from(ce.values());
}
function ji(e = hi) {
  const t = ce.get(e);
  if (!t)
    throw new Error(`getPersonality: unknown personality id "${e}"`);
  return t;
}
const yi = 0.75;
function Dt(e) {
  const { subject: t, relation: n, object: r, negated: i } = e.conclusion;
  return `${t} ${i ? "不" : ""}${n} ${r}`;
}
function Oi(e) {
  const t = Dt(e);
  return e.steps.length === 0 ? t : `${t}（推理路径：${e.path.join(" → ")}）`;
}
function Ei(e) {
  return Math.min(...e.map((t) => t.confidence));
}
const Si = Object.freeze([
  "subject",
  "relation",
  "object",
  "name",
  "intent"
]);
function wi(e) {
  for (const t of Si)
    if (e.missingSlots.includes(t)) return t;
  return e.clarificationKind === "uncertain-name" ? "name" : "intent";
}
const yt = {
  id: "default-v1",
  plan(e) {
    const { answers: t, query: n } = e;
    if (t.length === 0)
      return {
        mode: "no-answer",
        showEvidence: !1,
        isUncertain: !1,
        confidence: 0,
        explanation: e.explanation
      };
    const r = n.explain === !0, i = Ei(t);
    return {
      mode: r ? "explained" : "direct",
      showEvidence: r,
      isUncertain: i < yi,
      confidence: i,
      explanation: (r ? t.map(Oi) : t.map(Dt)).join("；")
    };
  },
  planClarification(e) {
    return Object.freeze({
      clarificationKind: e.clarificationKind,
      focus: wi(e),
      candidateLabels: Object.freeze([...e.candidateLabels]),
      reasonCategory: e.reasonCategory,
      ...e.relation === void 0 ? {} : { relation: e.relation },
      ...e.contextLabels === void 0 ? {} : {
        contextLabels: Object.freeze([
          ...e.contextLabels
        ])
      }
    });
  }
}, Ci = "isa-transitivity";
function Ri(e) {
  const t = [];
  let n = {
    subject: e[0].subject,
    relation: p.IsA,
    object: e[0].object,
    negated: !1
  };
  for (let r = 1; r < e.length; r += 1) {
    const i = e[r], c = {
      subject: n.subject,
      relation: p.IsA,
      object: i.object,
      negated: !1
    };
    t.push({
      ruleId: Ci,
      description: `${n.subject} 属于 ${n.object}，${i.subject} 属于 ${i.object} ⇒ ${c.subject} 属于 ${c.object}`,
      premises: [n, { subject: i.subject, relation: p.IsA, object: i.object, negated: !1 }],
      conclusion: c
    }), n = c;
  }
  return t;
}
function Ot(e) {
  const t = e[0].subject, n = e[e.length - 1].object, r = [t, ...e.map((c) => c.object)], i = e.reduce((c, s) => c * s.confidence, 1);
  return {
    conclusion: { subject: t, relation: p.IsA, object: n, negated: !1 },
    confidence: i,
    steps: Ri(e),
    path: r
  };
}
function ki(e, t) {
  const n = /* @__PURE__ */ new Set([t.subject]), r = [
    { node: t.subject, records: [] }
  ], i = [];
  let c = 0;
  for (; c < r.length; ) {
    const s = r[c];
    c += 1;
    const a = e.match({
      subject: s.node,
      relation: p.IsA,
      negated: !1
    });
    for (const o of a) {
      if (n.has(o.object)) continue;
      n.add(o.object);
      const d = [...s.records, o];
      if (t.targetObject === o.object)
        return d.length >= 2 ? [Ot(d)] : [];
      r.push({
        node: o.object,
        records: d
      }), t.targetObject === void 0 && d.length >= 2 && i.push(Ot(d));
    }
  }
  return i;
}
const zi = "relation-alignment-v1", Ii = Object.freeze([
  Object.freeze({
    queriedRelation: p.Is,
    matchedRelation: p.IsA,
    legacyClassificationOnly: !1
  }),
  Object.freeze({
    queriedRelation: p.IsA,
    matchedRelation: p.Is,
    legacyClassificationOnly: !0
  })
]), Ut = Object.freeze({
  id: zi,
  fallbackFor(e, t = {}) {
    return e.kind !== "object-of" || e.object !== void 0 || t.contextResolved === !0 || t.negatedInput === !0 ? null : Ii.find(
      ({ queriedRelation: n }) => n === e.relation
    ) ?? null;
  }
});
function Le(e, t, n, r = Ut) {
  return Object.freeze({
    mode: e,
    queriedRelation: t,
    matchedRelation: n,
    policyId: r.id
  });
}
const Ni = "目前还没有已知的相关事实。";
function Ti(e, t) {
  return t.match({
    subject: e.subject,
    relation: e.relation,
    ...e.object !== void 0 ? { object: e.object } : {}
  }).map((r) => ({
    conclusion: { subject: r.subject, relation: r.relation, object: r.object, negated: r.negated },
    confidence: r.confidence,
    steps: [],
    path: [r.subject, r.object]
  }));
}
function vi(e, t) {
  return e.relation !== p.IsA ? [] : ki(t, {
    subject: e.subject,
    ...e.object === void 0 ? {} : { targetObject: e.object }
  });
}
function Ai(e) {
  const { subject: t, relation: n, object: r, negated: i } = e.conclusion, c = i ? "不" : "";
  return e.steps.length === 0 ? `${t} ${c}${n} ${r}` : `${t} ${c}${n} ${r}（推理路径：${e.path.join(" → ")}）`;
}
function Ve(e, t) {
  const n = t.length > 0 ? t.map(Ai).join("；") : Ni;
  return {
    query: e,
    answers: t,
    conflicts: [],
    explanation: n
  };
}
function Et(e, t) {
  const n = Ti(e, t);
  if (e.object !== void 0 && n.length > 0)
    return Ve(e, n);
  const r = new Set(
    n.map((c) => c.conclusion.object)
  ), i = vi(e, t).filter(
    (c) => !r.has(c.conclusion.object)
  );
  return Ve(e, [...n, ...i]);
}
function xi(e) {
  if (e.negated || !e.object.startsWith("一种"))
    return null;
  const t = e.object.slice(2).trim();
  return t.length > 0 ? t : null;
}
function Li(e, t) {
  const n = [];
  for (const r of t.match({
    subject: e.subject,
    relation: p.Is,
    negated: !1
  })) {
    const i = xi(r);
    i !== null && n.push({
      conclusion: {
        subject: r.subject,
        relation: p.IsA,
        object: i,
        negated: !1
      },
      confidence: r.confidence,
      steps: [],
      path: [r.subject, i]
    });
  }
  return n;
}
function $i(e, t, n = {}, r = Ut) {
  const i = Et(e, t);
  if (i.answers.length > 0)
    return Object.freeze({
      result: i,
      relationResolution: Le(
        "exact",
        e.relation,
        e.relation,
        r
      )
    });
  const c = r.fallbackFor(e, n);
  if (c === null)
    return Object.freeze({
      result: i,
      relationResolution: Le(
        "exact",
        e.relation,
        e.relation,
        r
      )
    });
  const s = c.legacyClassificationOnly ? Li(e, t) : Et(
    {
      ...e,
      relation: c.matchedRelation
    },
    t
  ).answers;
  return Object.freeze({
    result: Ve(e, s),
    relationResolution: Le(
      "fallback",
      e.relation,
      c.matchedRelation,
      r
    )
  });
}
function nt(e) {
  return e !== null && Number.isFinite(e) && e >= 0;
}
function $e(e) {
  return nt(e) ? e < 1 ? "under-1ms" : e < 5 ? "1-5ms" : e < 16 ? "5-16ms" : e < 50 ? "16-50ms" : "over-50ms" : "unavailable";
}
function _i(e) {
  return !nt(e) || !Number.isSafeInteger(e) ? "unavailable" : e === 0 ? "0" : e < 100 ? "1-99" : e < 1e3 ? "100-999" : e < 5e3 ? "1000-4999" : "5000-plus";
}
function Ki(e) {
  return !nt(e) || !Number.isSafeInteger(e) ? "unavailable" : e === 0 ? "none" : e === 1 ? "direct" : e <= 5 ? "2-5" : e <= 20 ? "6-20" : e <= 50 ? "21-50" : "51-plus";
}
const qt = "0.1.0", Bt = 1, Ft = 1, Wt = 1, Mi = Object.freeze([
  "understood",
  "clarification",
  "no-understanding",
  "missing-knowledge",
  "relation-unsupported",
  "context-unresolved",
  "side-effect-blocked",
  "safe-fallback"
]), Pi = Object.freeze([
  "complete-passive-understanding",
  "missing-subject",
  "missing-relation",
  "missing-object",
  "ambiguous-intent",
  "conflicting-candidates",
  "insufficient-evidence",
  "missing-knowledge",
  "unsupported-relation",
  "unresolved-context",
  "blocked-side-effect",
  "semantic-runtime",
  "reasoner-error",
  "unknown-safe-fallback",
  "unclassified"
]), Di = Object.freeze([
  "属于",
  "是",
  "会",
  "喜欢",
  "在",
  "有",
  "意思是",
  "开发者",
  "none",
  "unknown"
]), Ui = Object.freeze([
  "ambiguous-intent",
  "missing-subject",
  "missing-relation",
  "missing-object",
  "uncertain-name",
  "uncertain-teaching",
  "conflicting-candidates",
  "none"
]), qi = Object.freeze([
  "under-1ms",
  "1-5ms",
  "5-16ms",
  "16-50ms",
  "over-50ms",
  "unavailable"
]), Bi = Object.freeze([
  "0",
  "1-99",
  "100-999",
  "1000-4999",
  "5000-plus",
  "unavailable"
]), Fi = Object.freeze([
  "direct",
  "2-5",
  "6-20",
  "21-50",
  "51-plus",
  "none",
  "unavailable"
]), Wi = Object.freeze([
  "aligned",
  "possible-mismatch",
  "no-alternative-known",
  "unavailable"
]), Ge = Object.freeze([
  "schemaVersion",
  "sunlandCoreVersion",
  "semanticSchemaVersion",
  "contextSchemaVersion",
  "resultCategory",
  "reasonCategory",
  "relationCategory",
  "semanticAdopted",
  "legacyFallback",
  "contextUsed",
  "clarificationKind",
  "pathLengthBucket",
  "knowledgeCountBucket",
  "totalDurationBucket",
  "semanticDurationBucket",
  "reasonerDurationBucket",
  "queriedRelation",
  "alternativeKnownRelation",
  "alignmentResult"
]), Vt = new Set(
  Mi
), Gt = new Set(
  Pi
), H = new Set(
  Di
), Yt = new Set(
  Ui
), Vi = new Set(Fi), Gi = new Set(
  Bi
), _e = new Set(qi), Qt = new Set(
  Wi
);
function Yi(e) {
  return typeof e == "object" && e !== null;
}
function I(e, t) {
  return typeof e == "string" && t.has(e);
}
function Qi(e) {
  const t = Reflect.ownKeys(e);
  return t.length === Ge.length && t.every(
    (n) => typeof n == "string" && Ge.includes(n)
  );
}
function Hi(e) {
  return Ge.every((t) => {
    const n = Object.getOwnPropertyDescriptor(e, t);
    return n !== void 0 && "value" in n && n.get === void 0 && n.set === void 0;
  });
}
function Ji(e) {
  return Object.freeze({
    schemaVersion: Wt,
    sunlandCoreVersion: qt,
    semanticSchemaVersion: Bt,
    contextSchemaVersion: Ft,
    resultCategory: Vt.has(e.resultCategory) ? e.resultCategory : "safe-fallback",
    reasonCategory: Gt.has(e.reasonCategory) ? e.reasonCategory : "unclassified",
    relationCategory: H.has(e.relationCategory) ? e.relationCategory : "unknown",
    semanticAdopted: e.semanticAdopted === !0,
    legacyFallback: e.legacyFallback === !0,
    contextUsed: e.contextUsed === !0,
    clarificationKind: Yt.has(
      e.clarificationKind
    ) ? e.clarificationKind : "none",
    pathLengthBucket: Ki(
      e.reasonerPathLength
    ),
    knowledgeCountBucket: _i(
      e.knowledgeCount
    ),
    totalDurationBucket: $e(e.totalDurationMs),
    semanticDurationBucket: $e(
      e.semanticDurationMs
    ),
    reasonerDurationBucket: $e(
      e.reasonerDurationMs
    ),
    queriedRelation: H.has(e.queriedRelation) ? e.queriedRelation : "unknown",
    alternativeKnownRelation: H.has(
      e.alternativeKnownRelation
    ) ? e.alternativeKnownRelation : "unknown",
    alignmentResult: Qt.has(e.alignmentResult) ? e.alignmentResult : "unavailable"
  });
}
function Xi(e) {
  try {
    return !Yi(e) || !Qi(e) || !Hi(e) ? !1 : e.schemaVersion === Wt && e.sunlandCoreVersion === qt && e.semanticSchemaVersion === Bt && e.contextSchemaVersion === Ft && I(e.resultCategory, Vt) && I(e.reasonCategory, Gt) && I(e.relationCategory, H) && typeof e.semanticAdopted == "boolean" && typeof e.legacyFallback == "boolean" && typeof e.contextUsed == "boolean" && I(e.clarificationKind, Yt) && I(e.pathLengthBucket, Vi) && I(
      e.knowledgeCountBucket,
      Gi
    ) && I(
      e.totalDurationBucket,
      _e
    ) && I(
      e.semanticDurationBucket,
      _e
    ) && I(
      e.reasonerDurationBucket,
      _e
    ) && I(e.queriedRelation, H) && I(
      e.alternativeKnownRelation,
      H
    ) && I(e.alignmentResult, Qt);
  } catch {
    return !1;
  }
}
function Zi(e) {
  return Xi(e) ? Object.freeze({
    schemaVersion: e.schemaVersion,
    sunlandCoreVersion: e.sunlandCoreVersion,
    semanticSchemaVersion: e.semanticSchemaVersion,
    contextSchemaVersion: e.contextSchemaVersion,
    resultCategory: e.resultCategory,
    reasonCategory: e.reasonCategory,
    relationCategory: e.relationCategory,
    semanticAdopted: e.semanticAdopted,
    legacyFallback: e.legacyFallback,
    contextUsed: e.contextUsed,
    clarificationKind: e.clarificationKind,
    pathLengthBucket: e.pathLengthBucket,
    knowledgeCountBucket: e.knowledgeCountBucket,
    totalDurationBucket: e.totalDurationBucket,
    semanticDurationBucket: e.semanticDurationBucket,
    reasonerDurationBucket: e.reasonerDurationBucket,
    queriedRelation: e.queriedRelation,
    alternativeKnownRelation: e.alternativeKnownRelation,
    alignmentResult: e.alignmentResult
  }) : null;
}
function ec(e) {
  return typeof e == "number" && Number.isFinite(e) && e >= 0 && e <= 1;
}
function v(e) {
  if (!ec(e))
    throw new RangeError("Confidence must be a finite number between 0 and 1.");
  return e;
}
function tc(e) {
  return Object.freeze({
    ...e,
    aliases: Object.freeze([...e.aliases]),
    baseWeight: v(e.baseWeight),
    constraints: Object.freeze({
      ...e.constraints,
      allowedCandidateKinds: Object.freeze([
        ...e.constraints.allowedCandidateKinds
      ])
    })
  });
}
const nc = Object.freeze(
  [
    {
      id: "greeting",
      canonical: "你好",
      aliases: ["你好", "您好", "嗨", "哈喽", "hello", "hi", "hey"],
      category: "conversation",
      baseWeight: 0.92,
      constraints: {
        matchMode: "whole-input",
        allowedCandidateKinds: ["intent"]
      },
      sideEffectSafe: !1
    },
    {
      id: "thanks",
      canonical: "谢谢",
      aliases: ["谢谢", "谢了", "感谢", "多谢", "thanks", "thank you", "thx"],
      category: "conversation",
      baseWeight: 0.92,
      constraints: {
        matchMode: "whole-input",
        allowedCandidateKinds: ["intent"]
      },
      sideEffectSafe: !1
    },
    {
      id: "goodbye",
      canonical: "再见",
      aliases: ["再见", "拜拜", "先走", "bye", "goodbye", "see you"],
      category: "conversation",
      baseWeight: 0.92,
      constraints: {
        matchMode: "whole-input",
        allowedCandidateKinds: ["intent"]
      },
      sideEffectSafe: !1
    },
    {
      id: "identity-name",
      canonical: "你叫什么",
      aliases: ["你叫什么", "你叫啥", "你的名字是什么"],
      category: "identity",
      baseWeight: 0.94,
      constraints: {
        matchMode: "whole-input",
        allowedCandidateKinds: ["query"]
      },
      sideEffectSafe: !1
    },
    {
      id: "identity-self",
      canonical: "你是谁",
      aliases: [
        "你是谁",
        "你是什么",
        "sunland ai是什么",
        "sunland ai 是什么"
      ],
      category: "identity",
      baseWeight: 0.94,
      constraints: {
        matchMode: "whole-input",
        allowedCandidateKinds: ["query"]
      },
      sideEffectSafe: !1
    },
    {
      id: "remember-name",
      canonical: "我叫",
      aliases: ["我叫", "我的名字是", "你可以叫我", "叫我"],
      category: "memory",
      baseWeight: 0.9,
      constraints: {
        matchMode: "prefix",
        allowedCandidateKinds: ["statement"],
        requiresFollowingEntity: !0
      },
      sideEffectSafe: !0
    },
    {
      id: "recall-name",
      canonical: "我叫什么",
      aliases: [
        "我叫什么",
        "我叫什么名字",
        "你记得我叫什么吗",
        "你记得我的名字吗",
        "你还记得我的名字吗",
        "还记得我是谁吗"
      ],
      category: "memory",
      baseWeight: 0.93,
      constraints: {
        matchMode: "whole-input",
        allowedCandidateKinds: ["query"]
      },
      sideEffectSafe: !1
    },
    {
      id: "teaching",
      canonical: "教你",
      aliases: ["教你", "告诉你一个知识", "记住这个事实"],
      category: "knowledge",
      baseWeight: 0.82,
      constraints: {
        matchMode: "prefix",
        allowedCandidateKinds: ["statement"],
        requiresFollowingEntity: !0
      },
      sideEffectSafe: !0
    },
    {
      id: "query-definition",
      canonical: "是什么",
      aliases: ["是什么", "是啥", "指什么", "什么意思"],
      category: "knowledge",
      baseWeight: 0.84,
      constraints: {
        matchMode: "infix",
        allowedCandidateKinds: ["query"]
      },
      sideEffectSafe: !1
    },
    {
      id: "is-a",
      canonical: "属于",
      aliases: ["属于", "是一种", "算是", "归类为", "是"],
      category: "relation",
      baseWeight: 0.86,
      constraints: {
        matchMode: "infix",
        allowedCandidateKinds: ["statement", "query"]
      },
      sideEffectSafe: !0
    },
    {
      id: "can",
      canonical: "会",
      aliases: ["会", "能", "能够"],
      category: "relation",
      baseWeight: 0.78,
      constraints: {
        matchMode: "infix",
        allowedCandidateKinds: ["statement", "query"]
      },
      sideEffectSafe: !0
    },
    {
      id: "has",
      canonical: "有",
      aliases: ["有", "拥有", "具备"],
      category: "relation",
      baseWeight: 0.8,
      constraints: {
        matchMode: "infix",
        allowedCandidateKinds: ["statement", "query"]
      },
      sideEffectSafe: !0
    },
    {
      id: "means",
      canonical: "意思是",
      aliases: ["意思是", "是什么意思", "表示", "指的是"],
      category: "relation",
      baseWeight: 0.84,
      constraints: {
        matchMode: "infix",
        allowedCandidateKinds: ["statement", "query"]
      },
      sideEffectSafe: !0
    }
  ].map(tc)
), rc = Object.freeze({
  "，": ",",
  "。": ".",
  "？": "?",
  "！": "!",
  "；": ";",
  "：": ":",
  "（": "(",
  "）": ")",
  "【": "[",
  "】": "]",
  "“": '"',
  "”": '"',
  "‘": "'",
  "’": "'",
  "～": "~"
}), ic = /* @__PURE__ */ new Set(["嗯", "呃", "唔"]), cc = /* @__PURE__ */ new Set(["呀", "啊", "呢", "哦", "啦"]), sc = /[\s,.;:!?'"()[\]~]/u;
function D(e, t) {
  return Object.freeze({ start: e, end: t });
}
function J(e) {
  return Object.freeze({
    ...e,
    rawRange: Object.freeze({ ...e.rawRange })
  });
}
function ac(e) {
  const t = [];
  let n = 0;
  for (const r of e) {
    const i = n;
    n += r.length, t.push(
      Object.freeze({
        text: r,
        rawRange: D(i, n)
      })
    );
  }
  return t;
}
function oc(e, t) {
  const n = ac(e), r = [];
  let i = 0;
  for (; i < n.length; ) {
    const c = n[i];
    if (/\s/u.test(c.text)) {
      const a = i;
      let o = i + 1;
      for (; o < n.length && /\s/u.test(n[o].text); )
        o += 1;
      const d = n.slice(a, o), l = D(
        d[0].rawRange.start,
        d[d.length - 1].rawRange.end
      ), b = e.slice(l.start, l.end);
      a === 0 || o === n.length ? t.push(
        J({
          stage: "surface",
          kind: "whitespace-trimmed",
          rawRange: l,
          sourceText: b,
          targetText: ""
        })
      ) : (r.push(Object.freeze({ text: " ", rawRange: l })), b !== " " && t.push(
        J({
          stage: "surface",
          kind: "whitespace-collapsed",
          rawRange: l,
          sourceText: b,
          targetText: " "
        })
      )), i = o;
      continue;
    }
    const s = rc[c.text];
    s !== void 0 ? (r.push(
      Object.freeze({
        text: s,
        rawRange: c.rawRange
      })
    ), t.push(
      J({
        stage: "surface",
        kind: "punctuation-normalized",
        rawRange: c.rawRange,
        sourceText: c.text,
        targetText: s
      })
    )) : r.push(c), i += 1;
  }
  return r;
}
function ge(e) {
  return e !== void 0 && sc.test(e.text);
}
function uc(e, t) {
  let n = 0, r = e.length;
  for (; n < r && ic.has(e[n].text) && ge(e[n + 1]); ) {
    const i = e[n];
    let c = n + 1;
    for (; c < r && ge(e[c]); )
      c += 1;
    const s = e.slice(n, c), a = D(
      i.rawRange.start,
      s[s.length - 1].rawRange.end
    );
    t.push(
      J({
        stage: "match-key",
        kind: "edge-filler-removed",
        rawRange: a,
        sourceText: s.map((o) => o.text).join(""),
        targetText: ""
      })
    ), n = c;
  }
  for (; r > n && cc.has(e[r - 1].text) && ge(e[r - 2]); ) {
    const i = e[r - 1];
    let c = r - 1;
    for (; c > n && ge(e[c - 1]); )
      c -= 1;
    const s = e.slice(c, r), a = D(
      s[0].rawRange.start,
      i.rawRange.end
    );
    t.push(
      J({
        stage: "match-key",
        kind: "edge-filler-removed",
        rawRange: a,
        sourceText: s.map((o) => o.text).join(""),
        targetText: ""
      })
    ), r = c;
  }
  return e.slice(n, r);
}
function lc(e, t) {
  const n = uc(
    e,
    t
  ), r = [];
  for (const i of n) {
    const c = i.text.toLocaleLowerCase("und");
    r.push(Object.freeze({ text: c, rawRange: i.rawRange })), c !== i.text && t.push(
      J({
        stage: "match-key",
        kind: "case-folded",
        rawRange: i.rawRange,
        sourceText: i.text,
        targetText: c
      })
    );
  }
  return r;
}
function St(e) {
  const t = [];
  let n = "";
  for (const r of e) {
    n += r.text;
    for (let i = 0; i < r.text.length; i += 1)
      t.push(r.rawRange);
  }
  return Object.freeze({
    text: n,
    mapping: Object.freeze(t)
  });
}
function fc(e) {
  const t = [], n = oc(e, t), r = lc(n, t), i = St(n), c = St(r);
  return Object.freeze({
    raw: e,
    surface: i.text,
    matchKey: c.text,
    surfaceToRaw: i.mapping,
    matchKeyToRaw: c.mapping,
    transformations: Object.freeze(t)
  });
}
function q(e, t, n, r) {
  const i = t === "surface" ? e.surface : e.matchKey, c = t === "surface" ? e.surfaceToRaw : e.matchKeyToRaw;
  if (!Number.isInteger(n) || !Number.isInteger(r) || n < 0 || r < n || r > i.length)
    throw new RangeError(
      `Normalized range must be within ${t} UTF-16 bounds.`
    );
  if (n === r) {
    if (n < c.length)
      return D(c[n].start, c[n].start);
    if (c.length > 0) {
      const o = c[c.length - 1];
      return D(o.end, o.end);
    }
    return D(0, 0);
  }
  let s = c[n].start, a = c[n].end;
  for (let o = n + 1; o < r; o += 1)
    s = Math.min(s, c[o].start), a = Math.max(a, c[o].end);
  return D(s, a);
}
const h = v, m = Object.freeze({
  producerWeight: Object.freeze({
    "legacy-regex": h(0.9),
    lexicon: h(0.8),
    "relation-pattern": h(0.72),
    context: h(0.64)
  }),
  legacy: Object.freeze({
    unknown: h(0.08),
    statement: h(0.91),
    query: h(0.92),
    intentFloor: h(0.88)
  }),
  lexicon: Object.freeze({
    aliasWeightShare: h(0.82),
    coverageWeightShare: h(0.18),
    exactInputBonus: h(0.04),
    entityCompleteBonus: h(0.08),
    sideEffectPenalty: h(0.03)
  }),
  relation: Object.freeze({
    base: h(0.48),
    conceptWeightShare: h(0.2),
    subjectBonus: h(0.12),
    objectBonus: h(0.12),
    queryShapeBonus: h(0.12),
    statementShapeBonus: h(0.14),
    missingSlotPenalty: h(0.16),
    sideEffectPenalty: h(0.05),
    weakSingleCharacterPenalty: h(0.08)
  }),
  context: Object.freeze({
    resolvedQuery: h(0.86),
    unresolvedReference: h(0.48),
    inheritedSubject: h(0.14),
    inheritedRelation: h(0.12)
  }),
  feature: Object.freeze({
    directSelf: h(0.9),
    indirectSelf: h(0.7),
    explicitName: h(0.94),
    questionCue: h(0.75),
    negationCue: h(0.9),
    structuralTeaching: h(0.68),
    definitionQuery: h(0.84)
  }),
  producerTieBreak: Object.freeze({
    "legacy-regex": 0,
    lexicon: 1,
    "relation-pattern": 2,
    context: 3
  })
});
function ye(e) {
  return v(Math.min(1, Math.max(0, e)));
}
function Ce(e, t = [], n = []) {
  const r = t.reduce((c, s) => c + s, 0), i = n.reduce((c, s) => c + s, 0);
  return ye(e + r - i);
}
function dc(e, t, n, r) {
  const i = n.length === 0 ? 0 : Math.min(1, t.length / n.length), c = e * m.lexicon.aliasWeightShare + i * m.lexicon.coverageWeightShare;
  return Ce(
    c,
    r ? [m.lexicon.exactInputBonus] : []
  );
}
const mc = Object.freeze(
  [
    "为什么",
    "有没有",
    "是不是",
    "会不会",
    "还是",
    "什么",
    "啥",
    "谁",
    "哪里",
    "哪",
    "怎么",
    "吗",
    "?"
  ].map(
    (e) => Object.freeze({
      value: e,
      kind: "question-cue",
      key: `question:${e}`
    })
  )
), bc = Object.freeze(
  ["不是", "不会", "不能", "没有", "不", "没", "别"].map(
    (e) => Object.freeze({
      value: e,
      kind: "negation-cue",
      key: `negation:${e}`
    })
  )
), gc = Object.freeze([
  Object.freeze({
    value: "sunland ai",
    canonical: "Sunland AI · Beta",
    confidence: m.feature.directSelf
  }),
  Object.freeze({
    value: "你",
    canonical: "Sunland AI · Beta",
    confidence: m.feature.directSelf
  }),
  Object.freeze({
    value: "霜蓝",
    canonical: "霜蓝",
    confidence: m.feature.indirectSelf
  })
]), hc = /* @__PURE__ */ new Set(["is-a", "can", "has", "means"]), pc = /* @__PURE__ */ new Set(["什么", "什么名字", "谁", "吗"]), Ye = /[a-z0-9]/iu, Qe = /[\s,.;:!?'"()[\]~]/u;
function rt(e, t) {
  return Object.freeze({ start: e, end: t });
}
function se(e, t, n, r, i) {
  return Object.freeze({
    kind: e,
    key: t,
    value: n,
    rawRange: Object.freeze({ ...r }),
    weight: i
  });
}
function wt(e, t) {
  return t < 0 || t >= e.length ? !0 : !Ye.test(e[t]);
}
function Ht(e, t, n, r) {
  const i = t[0], c = t[t.length - 1], s = i === void 0 || !Ye.test(i) || wt(e, n - 1), a = c === void 0 || !Ye.test(c) || wt(e, r);
  return s && a;
}
function Jt(e, t) {
  return e.start < t.end && t.start < e.end;
}
function jc(e) {
  const t = [];
  for (const n of nc) {
    const r = [], i = [...n.aliases].sort(
      (s, a) => a.length - s.length || s.localeCompare(a)
    );
    for (const s of i) {
      const a = s.trim().replace(/\s+/gu, " ").toLocaleLowerCase("und");
      let o = 0;
      for (; a.length > 0; ) {
        const d = e.matchKey.indexOf(a, o);
        if (d < 0)
          break;
        const l = d + a.length;
        if (o = d + 1, !Ht(e.matchKey, a, d, l))
          continue;
        const b = q(
          e,
          "matchKey",
          d,
          l
        ), g = dc(
          n.baseWeight,
          a,
          e.matchKey,
          e.matchKey === a
        ), C = se(
          "lexicon-alias",
          n.id,
          s,
          b,
          g
        ), k = Object.freeze({
          id: n.id,
          canonical: n.canonical,
          matchedAlias: s,
          confidence: g,
          evidence: Object.freeze([C])
        });
        r.push(
          Object.freeze({
            entry: n,
            alias: s,
            start: d,
            end: l,
            rawRange: b,
            feature: C,
            concept: k
          })
        );
      }
    }
    r.sort(
      (s, a) => s.start - a.start || a.end - a.start - (s.end - s.start) || s.alias.localeCompare(a.alias)
    );
    const c = [];
    for (const s of r)
      c.some((a) => Jt(a, s)) || c.push(s);
    t.push(...c);
  }
  return Object.freeze(
    t.sort(
      (n, r) => n.start - r.start || n.end - r.end || n.entry.id.localeCompare(r.entry.id)
    )
  );
}
function Ct(e, t, n) {
  const r = [], i = [...t].sort(
    (c, s) => s.value.length - c.value.length
  );
  for (const c of i) {
    let s = 0;
    for (; c.value.length > 0; ) {
      const a = e.matchKey.indexOf(c.value, s);
      if (a < 0)
        break;
      const o = a + c.value.length;
      if (s = a + 1, r.some(
        (l) => a < l.end && l.start < o
      ))
        continue;
      const d = q(
        e,
        "matchKey",
        a,
        o
      );
      r.push(
        Object.freeze({
          start: a,
          end: o,
          feature: se(
            c.kind,
            c.key,
            c.value,
            d,
            n
          )
        })
      );
    }
  }
  return Object.freeze(
    r.sort(
      (c, s) => c.start - s.start || c.end - s.end
    ).map((c) => c.feature)
  );
}
function yc(e, t, n) {
  let r = t, i = n;
  for (; r < i && Qe.test(e[r]); )
    r += 1;
  for (; i > r && Qe.test(e[i - 1]); )
    i -= 1;
  return rt(r, i);
}
function it(e, t, n, r, i, c) {
  const s = q(
    e,
    "matchKey",
    r,
    i
  );
  return Object.freeze({
    kind: t,
    value: n,
    rawText: e.raw.slice(s.start, s.end),
    start: s.start,
    end: s.end,
    source: "explicit",
    confidence: c
  });
}
function Oc(e) {
  const t = [];
  for (const n of gc) {
    let r = 0;
    for (; n.value.length > 0; ) {
      const i = e.matchKey.indexOf(n.value, r);
      if (i < 0)
        break;
      const c = i + n.value.length;
      r = c, Ht(
        e.matchKey,
        n.value,
        i,
        c
      ) && t.push(
        it(
          e,
          "self",
          n.canonical,
          i,
          c,
          n.confidence
        )
      );
    }
  }
  return Object.freeze(t);
}
function Ec(e, t) {
  const n = [];
  for (const r of t) {
    if (r.entry.id !== "remember-name")
      continue;
    let i = r.end, c = e.matchKey.length;
    for (; i < c && Qe.test(e.matchKey[i]); )
      i += 1;
    const s = e.matchKey.slice(i).search(/[,;!?]/u);
    s >= 0 && (c = i + s);
    const a = yc(e.matchKey, i, c);
    if (a.start >= a.end)
      continue;
    const o = q(
      e,
      "matchKey",
      a.start,
      a.end
    ), d = e.raw.slice(o.start, o.end).trim().replace(/\s+/gu, " "), l = d.toLocaleLowerCase("und");
    d.length === 0 || pc.has(l) || /^(?:不|没|别)/u.test(l) || n.push(
      it(
        e,
        "person-name",
        d,
        a.start,
        a.end,
        m.feature.explicitName
      )
    );
  }
  return Object.freeze(
    n.filter(
      (r, i) => n.findIndex(
        (c) => c.start === r.start && c.end === r.end && c.value === r.value
      ) === i
    )
  );
}
function Sc(e, t) {
  const n = t.filter(
    (i) => hc.has(i.entry.id)
  ).sort(
    (i, c) => i.start - c.start || c.end - c.start - (i.end - i.start) || i.entry.id.localeCompare(c.entry.id)
  ), r = [];
  for (const i of n)
    r.some((c) => Jt(c, i)) || r.push(i);
  return Object.freeze(
    r.map((i) => {
      const c = it(
        e,
        "relation",
        i.entry.canonical,
        i.start,
        i.end,
        i.concept.confidence
      );
      return Object.freeze({
        conceptId: i.entry.id,
        canonical: i.entry.canonical,
        alias: i.alias,
        matchKeyRange: rt(i.start, i.end),
        entity: c,
        confidence: i.concept.confidence,
        evidence: Object.freeze([i.feature])
      });
    })
  );
}
function wc(e, t) {
  return t.length > 0 ? Object.freeze([]) : Object.freeze(
    e.map(
      (n) => se(
        "teaching-cue",
        `teaching:${n.conceptId}`,
        n.alias,
        rt(n.entity.start, n.entity.end),
        m.feature.structuralTeaching
      )
    )
  );
}
function Cc(e) {
  const t = jc(e), n = Object.freeze(
    t.map((g) => g.concept)
  ), r = Ct(
    e,
    mc,
    m.feature.questionCue
  ), i = Ct(
    e,
    bc,
    m.feature.negationCue
  ), c = Oc(e), s = Ec(e, t), a = Sc(e, t), o = t.filter((g) => g.entry.id === "teaching").map(
    (g) => se(
      "teaching-cue",
      "teaching:explicit",
      g.alias,
      g.rawRange,
      g.concept.confidence
    )
  ), d = Object.freeze([
    ...o,
    ...wc(a, r)
  ]), l = Object.freeze(
    t.filter((g) => g.entry.id === "query-definition").map(
      (g) => se(
        "definition-query",
        "query:definition",
        g.alias,
        g.rawRange,
        m.feature.definitionQuery
      )
    )
  ), b = Object.freeze([
    ...c,
    ...s,
    ...a.map((g) => g.entity)
  ]);
  return Object.freeze({
    input: e,
    concepts: n,
    entities: b,
    questionCues: r,
    negationCues: i,
    selfReferences: c,
    personNames: s,
    relations: a,
    teachingCues: d,
    definitionQueryCues: l
  });
}
const T = Object.freeze({
  maximumTurns: 6,
  maximumConceptsPerTurn: 8,
  maximumEntitiesPerTurn: 4,
  maximumEntityValueLength: 80,
  maximumRelationLength: 48,
  maximumTurnIdLength: 128
}), Rc = /* @__PURE__ */ new Set([
  "Greeting",
  "Thanks",
  "Farewell",
  "Identity",
  "RememberName",
  "RecallName"
]), kc = /* @__PURE__ */ new Set([
  "object-of",
  "verify",
  "locate"
]), zc = /* @__PURE__ */ new Set([
  "subject",
  "object",
  "self"
]), Ic = /* @__PURE__ */ new Set([
  "它",
  "这个",
  "那个",
  "这",
  "那"
]), Nc = /* @__PURE__ */ new Set([
  "你",
  "sunland ai",
  "sunland ai · beta"
]);
function Re(e) {
  return typeof e == "object" && e !== null;
}
function X(e, t) {
  if (typeof e != "string") return null;
  const n = e.trim().replace(/\s+/gu, " ");
  return n.length === 0 || n.length > t ? null : n;
}
function ct(e) {
  return Ic.has(
    e.trim().replace(/\s+/gu, " ").toLocaleLowerCase("und")
  );
}
function st(e) {
  return Nc.has(
    e.trim().replace(/\s+/gu, " ").toLocaleLowerCase("und")
  );
}
function Rt(e) {
  if (!Re(e) || !zc.has(e.kind))
    return null;
  const t = X(
    e.value,
    T.maximumEntityValueLength
  );
  return t === null ? null : Object.freeze({
    kind: e.kind,
    value: t
  });
}
function Tc(e) {
  if (!Re(e) || !kc.has(e.kind))
    return;
  const t = X(
    e.relation,
    T.maximumRelationLength
  );
  if (!(t === null || typeof e.hasObject != "boolean"))
    return Object.freeze({
      kind: e.kind,
      relation: t,
      hasObject: e.hasObject
    });
}
function vc(e) {
  if (!Re(e) || e.speaker !== "user" && e.speaker !== "assistant")
    return null;
  const t = X(
    e.turnId,
    T.maximumTurnIdLength
  );
  if (t === null) return null;
  const n = typeof e.acceptedIntent == "string" && Rc.has(e.acceptedIntent) ? e.acceptedIntent : void 0, r = Object.freeze(
    (Array.isArray(e.concepts) ? e.concepts : []).map(
      (o) => X(
        o,
        T.maximumEntityValueLength
      )
    ).filter((o) => o !== null).slice(0, T.maximumConceptsPerTurn)
  ), i = Object.freeze(
    (Array.isArray(e.entityReferences) ? e.entityReferences : []).map(Rt).filter(
      (o) => o !== null
    ).slice(0, T.maximumEntitiesPerTurn)
  ), c = Rt(e.focusEntity), s = X(
    e.relation,
    T.maximumRelationLength
  ), a = Tc(e.queryShape);
  return Object.freeze({
    turnId: t,
    speaker: e.speaker,
    ...n === void 0 ? {} : { acceptedIntent: n },
    concepts: r,
    entityReferences: i,
    ...c === null ? {} : { focusEntity: c },
    ...s === null ? {} : { relation: s },
    ...a === void 0 ? {} : { queryShape: a }
  });
}
function Xt() {
  return Object.freeze({
    schemaVersion: 1,
    version: 0,
    recentTurns: Object.freeze([])
  });
}
function ee(e) {
  if (!Re(e)) return Xt();
  const t = typeof e.version == "number" && Number.isSafeInteger(e.version) && e.version >= 0 ? e.version : 0, n = Object.freeze(
    (Array.isArray(e.recentTurns) ? e.recentTurns : []).map(vc).filter((r) => r !== null).slice(-T.maximumTurns)
  );
  return Object.freeze({
    schemaVersion: 1,
    version: t,
    recentTurns: n
  });
}
function Ke(e, t) {
  return Object.freeze({ kind: e, value: t.trim().replace(/\s+/gu, " ") });
}
function kt(e) {
  return st(e);
}
function Ac(e) {
  const t = [
    e.selectedCandidate,
    ...e.secondaryCandidates
  ];
  return Object.freeze(
    [...new Set(t.flatMap(({ concepts: n }) => n.map(({ id: r }) => r)))].sort().slice(0, T.maximumConceptsPerTurn)
  );
}
function xc(e, t, n) {
  const r = Ac(n);
  switch (t.type) {
    case "query": {
      const i = Ke(
        kt(t.subject) ? "self" : "subject",
        kt(t.subject) ? "Sunland AI · Beta" : t.subject
      );
      return Object.freeze({
        turnId: e,
        speaker: "user",
        concepts: r,
        entityReferences: Object.freeze([i]),
        focusEntity: i,
        relation: t.relation,
        queryShape: Object.freeze({
          kind: t.kind,
          relation: t.relation,
          hasObject: t.object !== void 0
        })
      });
    }
    case "statement": {
      const i = Ke("subject", t.subject);
      return Object.freeze({
        turnId: e,
        speaker: "user",
        concepts: r,
        entityReferences: Object.freeze([i]),
        focusEntity: i,
        relation: t.relation
      });
    }
    case "intent": {
      if (t.intent === "Identity") {
        const i = Ke("self", "Sunland AI · Beta");
        return Object.freeze({
          turnId: e,
          speaker: "user",
          acceptedIntent: t.intent,
          concepts: r,
          entityReferences: Object.freeze([i]),
          focusEntity: i,
          relation: t.entities[1] === "capability" ? "会" : "是"
        });
      }
      return t.intent === "RememberName" ? Object.freeze({
        turnId: e,
        speaker: "user",
        acceptedIntent: t.intent,
        concepts: r,
        entityReferences: Object.freeze([])
      }) : null;
    }
    case "unknown":
      return null;
  }
}
function Lc(e) {
  const t = ee(e.context);
  if (!e.canCommit || e.decision.kind !== "accept" || e.executedResult === null)
    return Object.freeze({
      kind: "none",
      baseVersion: t.version
    });
  const n = X(
    e.turnId,
    T.maximumTurnIdLength
  );
  if (n === null)
    return Object.freeze({
      kind: "none",
      baseVersion: t.version
    });
  const r = xc(
    n,
    e.executedResult,
    e.decision
  );
  if (r === null)
    return Object.freeze({
      kind: "none",
      baseVersion: t.version
    });
  const i = t.version + 1, c = Object.freeze({
    schemaVersion: 1,
    version: i,
    recentTurns: Object.freeze(
      [...t.recentTurns, r].slice(
        -T.maximumTurns
      )
    )
  });
  return Object.freeze({
    kind: "replace",
    baseVersion: t.version,
    nextVersion: i,
    context: c
  });
}
function za(e, t) {
  const n = ee(e);
  return t.kind !== "replace" || t.baseVersion !== n.version || t.nextVersion !== t.baseVersion + 1 || t.context.version !== t.nextVersion ? n : ee(t.context);
}
function ke(e) {
  return e.trim().replace(/\s+/gu, " ").toLocaleLowerCase("und");
}
function $c(e) {
  return [...e.recentTurns].reverse().find(
    (t) => t.relation !== void 0 || t.focusEntity !== void 0 || t.entityReferences.length > 0
  );
}
function Zt(e) {
  const t = $c(e);
  if (t === void 0)
    return Object.freeze({ kind: "none", entities: Object.freeze([]) });
  if (t.focusEntity !== void 0)
    return Object.freeze({
      kind: "unique",
      entities: Object.freeze([t.focusEntity])
    });
  const n = /* @__PURE__ */ new Set(), r = Object.freeze(
    t.entityReferences.filter(({ kind: i }) => i === "subject" || i === "self").filter((i) => {
      const c = ke(i.value);
      return n.has(c) ? !1 : (n.add(c), !0);
    })
  );
  return r.length === 1 ? Object.freeze({ kind: "unique", entities: r }) : r.length > 1 ? Object.freeze({ kind: "ambiguous", entities: r }) : Object.freeze({ kind: "none", entities: r });
}
function _c(e) {
  var t;
  return ((t = [...e.recentTurns].reverse().find(({ relation: n }) => n !== void 0)) == null ? void 0 : t.relation) ?? null;
}
function Oe(e, t, n, r, i) {
  return Object.freeze({
    kind: e,
    value: t,
    rawText: n,
    start: r.start,
    end: r.end,
    source: i,
    confidence: m.context.resolvedQuery
  });
}
function ae(e, t, n, r) {
  return Object.freeze({
    kind: "context-reference",
    key: e,
    value: t,
    weight: n,
    ...r === void 0 ? {} : { rawRange: Object.freeze({ ...r }) }
  });
}
function zt(e, t, n) {
  return Object.freeze({
    id: e,
    canonical: t,
    confidence: m.context.resolvedQuery,
    evidence: n
  });
}
function oe(e, t, n, r, i, c) {
  return Object.freeze({
    id: e,
    producer: "context",
    producerWeight: m.producerWeight.context,
    result: t,
    concepts: Object.freeze([...c]),
    entities: Object.freeze([...n]),
    confidence: t === null ? m.context.unresolvedReference : m.context.resolvedQuery,
    evidence: Object.freeze([...r]),
    missingSlots: Object.freeze([...i]),
    sideEffect: "none"
  });
}
function at(e, t) {
  const n = e.input.matchKey.indexOf(t);
  return n < 0 ? Object.freeze({ start: 0, end: 0 }) : q(
    e.input,
    "matchKey",
    n,
    n + t.length
  );
}
function He(e) {
  return ct(e);
}
function te(e) {
  return st(e);
}
function Me(e, t, n, r, i) {
  const c = at(e, ke(n.subject)), s = e.input.raw.slice(c.start, c.end), a = Oe(
    te(r) ? "self" : "subject",
    te(r) ? "Sunland AI · Beta" : r,
    s,
    c,
    i
  ), o = Object.freeze({
    ...n,
    subject: a.value
  }), d = ae(
    "context:resolved-subject",
    a.value,
    m.context.inheritedSubject,
    c
  );
  return oe(
    `context:query:${o.subject}:${o.relation}:${o.kind}`,
    o,
    Object.freeze([
      a,
      ...t.entities.filter(({ kind: l }) => l !== "subject")
    ]),
    Object.freeze([...t.evidence, d]),
    Object.freeze([]),
    t.concepts
  );
}
function Kc(e, t, n, r) {
  const i = at(e, ke(n.subject)), c = Object.freeze([
    ...t.evidence,
    ae(
      r.kind === "ambiguous" ? "context:ambiguous-subject" : "context:missing-subject",
      n.subject,
      m.context.unresolvedReference,
      i
    )
  ]), s = r.entities.map(
    (a) => Oe(
      a.kind === "self" ? "self" : "subject",
      a.value,
      "",
      Object.freeze({ start: 0, end: 0 }),
      "context"
    )
  );
  return oe(
    `context:partial:${n.relation}:${r.kind}`,
    null,
    Object.freeze(s),
    c,
    Object.freeze(["subject"]),
    t.concepts
  );
}
function Mc(e, t, n) {
  const r = Zt(n), i = [], c = [], s = t.some(
    ({ result: a }) => (a == null ? void 0 : a.type) === "query" && a.kind === "object-of" && a.relation === "意思是"
  );
  for (const a of t) {
    const o = a.result;
    if (s && a.producer === "legacy-regex" && (o == null ? void 0 : o.type) === "intent" && o.intent === "Identity") {
      c.push(a.id);
      continue;
    }
    if ((o == null ? void 0 : o.type) === "statement" && He(o.subject)) {
      const d = at(
        e,
        ke(o.subject)
      ), l = ae(
        "context:side-effect-subject-prohibited",
        o.subject,
        m.context.unresolvedReference,
        d
      );
      i.push(
        oe(
          `context:partial:side-effect-subject:${o.relation}`,
          null,
          Object.freeze([]),
          Object.freeze([...a.evidence, l]),
          Object.freeze(["subject"]),
          a.concepts
        )
      ), c.push(a.id);
      continue;
    }
    if ((o == null ? void 0 : o.type) === "query") {
      if (o.kind === "object-of" && o.relation === "意思是") {
        i.push(
          Me(
            e,
            a,
            o,
            o.subject,
            "explicit"
          )
        ), c.push(a.id);
        continue;
      }
      if (te(o.subject)) {
        i.push(
          Me(
            e,
            a,
            o,
            "Sunland AI · Beta",
            "explicit"
          )
        ), c.push(a.id);
        continue;
      }
      He(o.subject) && (c.push(a.id), r.kind === "unique" ? i.push(
        Me(
          e,
          a,
          o,
          r.entities[0].value,
          "context"
        )
      ) : i.push(
        Kc(
          e,
          a,
          o,
          r
        )
      ));
    }
  }
  return Object.freeze({
    candidates: Object.freeze(i),
    supersededCandidateIds: Object.freeze(c)
  });
}
function Pc(e, t) {
  var a;
  const n = e.input.surface.toLocaleLowerCase("und"), r = /^(?:那\s*)?(.+?)\s*呢$/u.exec(
    n
  );
  if (r === null) return null;
  const i = ((a = r[1]) == null ? void 0 : a.trim()) ?? "";
  if (i.length === 0) return null;
  const c = n.indexOf(i), s = q(
    e.input,
    "surface",
    c,
    c + i.length
  );
  if (te(i))
    return Object.freeze({
      value: "Sunland AI · Beta",
      rawRange: s,
      source: "explicit",
      ambiguousEntities: Object.freeze([])
    });
  if (He(i)) {
    const o = Zt(t);
    return o.kind !== "unique" ? Object.freeze({
      value: "",
      rawRange: s,
      source: "context",
      ambiguousEntities: o.entities
    }) : Object.freeze({
      value: o.entities[0].value,
      rawRange: s,
      source: "context",
      ambiguousEntities: Object.freeze([])
    });
  }
  return Object.freeze({
    value: e.input.raw.slice(s.start, s.end).trim().replace(/\s+/gu, " "),
    rawRange: s,
    source: "explicit",
    ambiguousEntities: Object.freeze([])
  });
}
function Dc(e, t) {
  const n = Pc(e, t);
  if (n === null) return null;
  const r = _c(t), i = ae(
    n.value.length === 0 ? "context:ambiguous-subject" : "context:ellipsis-subject",
    n.value,
    m.context.inheritedSubject,
    n.rawRange
  );
  if (n.value.length === 0 || r === null) {
    const l = Object.freeze([
      ...n.value.length === 0 ? ["subject"] : [],
      ...r === null ? ["relation"] : []
    ]), b = n.ambiguousEntities.map(
      (g) => Oe(
        g.kind === "self" ? "self" : "subject",
        g.value,
        "",
        Object.freeze({ start: 0, end: 0 }),
        "context"
      )
    );
    return oe(
      `context:ellipsis:partial:${l.join("+")}`,
      null,
      Object.freeze(b),
      Object.freeze([i]),
      l,
      Object.freeze([
        zt(
          "context-ellipsis",
          "context ellipsis",
          Object.freeze([i])
        )
      ])
    );
  }
  const c = Oe(
    te(n.value) ? "self" : "subject",
    te(n.value) ? "Sunland AI · Beta" : n.value,
    e.input.raw.slice(
      n.rawRange.start,
      n.rawRange.end
    ),
    n.rawRange,
    n.source
  ), s = ae(
    "context:inherited-relation",
    r,
    m.context.inheritedRelation
  ), a = r === "在" ? "locate" : "object-of", o = Object.freeze({
    type: "query",
    subject: c.value,
    relation: r,
    kind: a,
    raw: e.input.raw
  }), d = Object.freeze([i, s]);
  return oe(
    `context:ellipsis:query:${c.value}:${r}`,
    o,
    Object.freeze([c]),
    d,
    Object.freeze([]),
    Object.freeze([
      zt("context-ellipsis", "context ellipsis", d)
    ])
  );
}
function Uc(e, t, n) {
  var s;
  const r = Mc(
    e,
    t,
    n
  ), i = Dc(e, n), c = ((s = i == null ? void 0 : i.result) == null ? void 0 : s.type) === "query" ? t.filter(
    ({ producer: a, result: o }) => a === "legacy-regex" && (o == null ? void 0 : o.type) === "intent" && o.intent === "Identity"
  ).map(({ id: a }) => a) : [];
  return Object.freeze({
    candidates: Object.freeze([
      ...r.candidates,
      ...i === null ? [] : [i]
    ]),
    supersededCandidateIds: Object.freeze([
      ...r.supersededCandidateIds,
      ...c
    ])
  });
}
const qc = Object.freeze({
  Greeting: Object.freeze(["greeting"]),
  Thanks: Object.freeze(["thanks"]),
  Farewell: Object.freeze(["goodbye"]),
  Identity: Object.freeze(["identity-name", "identity-self"]),
  RememberName: Object.freeze(["remember-name"]),
  RecallName: Object.freeze(["recall-name"])
});
function Bc(e) {
  switch (e.type) {
    case "intent":
      return `intent:${e.intent}:${e.entities.join("|")}`;
    case "statement":
      return `statement:${e.subject}:${e.relation}:${e.object}:${e.negated}`;
    case "query":
      return `query:${e.kind}:${e.subject}:${e.relation}:${e.object ?? ""}`;
    case "unknown":
      return "unknown";
  }
}
function Fc(e, t) {
  if (e.type === "intent") {
    const n = qc[e.intent] ?? [];
    return Object.freeze(
      t.concepts.filter((r) => n.includes(r.id))
    );
  }
  return e.type === "statement" || e.type === "query" ? Object.freeze(
    t.concepts.filter(
      (n) => t.relations.some(
        (r) => r.conceptId === n.id && r.canonical === e.relation
      )
    )
  ) : Object.freeze([]);
}
function Wc(e) {
  switch (e.type) {
    case "intent":
      return v(
        Math.max(
          m.legacy.intentFloor,
          ye(e.confidence)
        )
      );
    case "statement":
      return m.legacy.statement;
    case "query":
      return m.legacy.query;
    case "unknown":
      return m.legacy.unknown;
  }
}
function Vc(e) {
  const t = Pt().parse(e.input.raw), n = Wc(t), r = Object.freeze({
    start: 0,
    end: e.input.raw.length
  }), i = Object.freeze([
    Object.freeze({
      kind: "legacy-regex",
      key: `legacy:${t.type}`,
      value: t.type,
      rawRange: r,
      weight: n
    })
  ]);
  return Object.freeze({
    id: `legacy-regex:${Bc(t)}`,
    producer: "legacy-regex",
    producerWeight: m.producerWeight["legacy-regex"],
    result: t,
    concepts: Fc(t, e),
    entities: e.entities,
    confidence: n,
    evidence: i,
    missingSlots: t.type === "unknown" ? Object.freeze(["interpretation"]) : Object.freeze([]),
    sideEffect: t.type === "statement" ? "knowledge-write" : "none"
  });
}
const Gc = Object.freeze({
  greeting: Object.freeze({ intent: "Greeting", sideEffect: "none" }),
  thanks: Object.freeze({ intent: "Thanks", sideEffect: "none" }),
  goodbye: Object.freeze({ intent: "Farewell", sideEffect: "none" }),
  "identity-name": Object.freeze({
    intent: "Identity",
    sideEffect: "none"
  }),
  "identity-self": Object.freeze({
    intent: "Identity",
    sideEffect: "none"
  }),
  "remember-name": Object.freeze({
    intent: "RememberName",
    sideEffect: "memory-write"
  }),
  "recall-name": Object.freeze({
    intent: "RecallName",
    sideEffect: "none"
  })
});
function en(e) {
  return e.evidence[0] ?? null;
}
function Yc(e, t) {
  var r, i;
  const n = ((i = (r = en(e)) == null ? void 0 : r.rawRange) == null ? void 0 : i.end) ?? 0;
  return [...t.personNames].filter((c) => c.start >= n).sort(
    (c, s) => c.start - s.start || c.end - s.end
  )[0] ?? null;
}
function Qc(e, t, n) {
  var i, c;
  const r = ((c = (i = en(e)) == null ? void 0 : i.rawRange) == null ? void 0 : c.start) ?? 0;
  return n.negationCues.some((s) => {
    const a = s.rawRange;
    return a !== void 0 && a.start >= r && a.end <= t.end;
  });
}
function Hc(e) {
  var n;
  const t = ((n = e.selfReferences[0]) == null ? void 0 : n.value) ?? "Sunland AI · Beta";
  return Object.freeze([t, "identity"]);
}
function Jc(e, t, n, r) {
  return Object.freeze({
    type: "intent",
    intent: e,
    entities: Object.freeze([...t]),
    confidence: n,
    raw: r
  });
}
function Xc(e, t) {
  const n = Gc[e.id];
  if (n === void 0)
    return null;
  let r = Object.freeze([]), i = Object.freeze([]);
  if (n.intent === "Identity" && (r = t.selfReferences, i = Hc(t)), n.intent === "RememberName") {
    const l = Yc(e, t);
    if (l === null || Qc(e, l, t))
      return null;
    r = Object.freeze([l]), i = Object.freeze([l.value]);
  }
  const c = r.length > 0 ? [m.lexicon.entityCompleteBonus] : [], s = n.sideEffect === "none" ? [] : [m.lexicon.sideEffectPenalty], a = Ce(
    e.confidence,
    c,
    s
  ), o = Jc(
    n.intent,
    i,
    a,
    t.input.raw
  ), d = Object.freeze([
    ...e.evidence,
    ...r.map(
      (l) => Object.freeze({
        kind: "entity-pattern",
        key: `entity:${l.kind}`,
        value: l.value,
        rawRange: Object.freeze({
          start: l.start,
          end: l.end
        }),
        weight: l.confidence
      })
    )
  ]);
  return Object.freeze({
    id: `lexicon:intent:${n.intent}:${i.join("|")}`,
    producer: "lexicon",
    producerWeight: m.producerWeight.lexicon,
    result: o,
    concepts: Object.freeze([e]),
    entities: r,
    confidence: a,
    evidence: d,
    missingSlots: Object.freeze([]),
    sideEffect: n.sideEffect
  });
}
function Zc(e) {
  const t = e.concepts.some(
    ({ id: n }) => n === "recall-name"
  );
  return Object.freeze(
    e.concepts.filter(
      ({ id: n }) => !(t && n === "remember-name")
    ).map((n) => Xc(n, e)).filter(
      (n) => n !== null
    )
  );
}
const tn = /[,;!?]/u, It = /[\s,.;:!?'"()[\]~]/u, nn = /* @__PURE__ */ new Set(["什么", "啥", "谁", "哪", "哪里"]), rn = /[吗呢]$/u, es = /(?:不是|不会|不能|没有|不|没)$/u;
function ts(e, t) {
  let n = 0;
  for (let c = t - 1; c >= 0; c -= 1)
    if (tn.test(e[c])) {
      n = c + 1;
      break;
    }
  const r = e.slice(n, t), i = r.lastIndexOf("和");
  return i >= 0 && /(?:什么|啥|谁|吗|呢|\?)/u.test(r.slice(0, i)) ? n + i + 1 : n;
}
function ns(e, t) {
  for (let n = t; n < e.length; n += 1)
    if (tn.test(e[n]))
      return n;
  return e.length;
}
function Ee(e, t, n) {
  let r = t, i = n;
  for (; r < i && It.test(e[r]); )
    r += 1;
  for (; i > r && It.test(e[i - 1]); )
    i -= 1;
  return r >= i ? null : Object.freeze({
    start: r,
    end: i,
    value: e.slice(r, i)
  });
}
function rs(e, t) {
  if (t === null)
    return Object.freeze({ segment: null, negated: !1 });
  const n = es.exec(t.value);
  return Object.freeze(n === null ? { segment: t, negated: !1 } : {
    segment: Ee(
      e,
      t.start,
      t.end - n[0].length
    ),
    negated: !0
  });
}
function is(e, t) {
  if (t === null)
    return null;
  const n = rn.exec(t.value);
  return n === null ? t : Ee(
    e,
    t.start,
    t.end - n[0].length
  );
}
function cn(e, t) {
  return q(
    e.input,
    "matchKey",
    t.start,
    t.end
  );
}
function cs(e, t) {
  const n = cn(e, t);
  return e.input.raw.slice(n.start, n.end).trim().replace(/\s+/gu, " ").replace(/^["“”'‘’]+|["“”'‘’]+$/gu, "");
}
function Nt(e, t, n, r) {
  const i = cn(e, n);
  return Object.freeze({
    kind: t,
    value: cs(e, n),
    rawText: e.input.raw.slice(i.start, i.end),
    start: i.start,
    end: i.end,
    source: "explicit",
    confidence: r
  });
}
function ss(e, t) {
  return e.concepts.find(
    (n) => n.id === t.conceptId && n.evidence.some(
      (r) => {
        var i;
        return ((i = r.rawRange) == null ? void 0 : i.start) === t.entity.start && r.rawRange.end === t.entity.end;
      }
    )
  ) ?? Object.freeze({
    id: t.conceptId,
    canonical: t.canonical,
    matchedAlias: t.alias,
    confidence: t.confidence,
    evidence: t.evidence
  });
}
function as(e, t) {
  return e.concepts.filter(
    (n) => n.id === "remember-name" || n.id === "recall-name"
  ).some(
    (n) => n.evidence.some((r) => {
      const i = r.rawRange;
      return i !== void 0 && t.entity.start >= i.start && t.entity.end <= i.end;
    })
  );
}
function os(e, t, n, r) {
  if (r !== null && nn.has(r.value.replace(rn, "")))
    return !0;
  const i = t < n ? q(
    e.input,
    "matchKey",
    t,
    n
  ) : null;
  return e.questionCues.some((c) => {
    const s = c.rawRange;
    return s !== void 0 && i !== null && s.start >= i.start && s.end <= i.end;
  });
}
function us(e, t, n, r, i, c) {
  return n === null ? null : i === "object-of" ? Object.freeze({
    type: "query",
    subject: n.value,
    relation: t.canonical,
    kind: "object-of",
    raw: e.input.raw
  }) : i === "verify" ? r === null ? null : Object.freeze({
    type: "query",
    subject: n.value,
    relation: t.canonical,
    object: r.value,
    kind: "verify",
    raw: e.input.raw
  }) : r === null ? null : Object.freeze({
    type: "statement",
    subject: n.value,
    relation: t.canonical,
    object: r.value,
    negated: c,
    raw: e.input.raw
  });
}
function ls(e, t) {
  if (as(e, t))
    return null;
  const n = e.input.matchKey, r = ts(n, t.matchKeyRange.start), i = ns(n, t.matchKeyRange.end), c = Ee(
    n,
    r,
    t.matchKeyRange.start
  ), s = rs(n, c), a = Ee(
    n,
    t.matchKeyRange.end,
    i
  ), o = is(n, a), d = os(
    e,
    r,
    i,
    o
  ), l = t.alias === "是什么意思" || o !== null && nn.has(o.value), b = l ? "object-of" : d ? "verify" : null, g = l ? null : o, C = s.segment === null ? null : Nt(
    e,
    "subject",
    s.segment,
    t.confidence
  ), k = g === null ? null : Nt(
    e,
    "object",
    g,
    t.confidence
  ), w = us(
    e,
    t,
    C,
    k,
    b,
    s.negated
  ), W = [];
  C === null && W.push("subject"), (b === null || b === "verify") && k === null && W.push("object");
  const ue = (w == null ? void 0 : w.type) === "statement" ? "knowledge-write" : "none", A = [
    t.confidence * m.relation.conceptWeightShare,
    ...C === null ? [] : [m.relation.subjectBonus],
    ...k === null ? [] : [m.relation.objectBonus],
    b !== null ? m.relation.queryShapeBonus : m.relation.statementShapeBonus
  ], ze = [
    ...W.map(
      () => m.relation.missingSlotPenalty
    ),
    ...ue === "none" ? [] : [m.relation.sideEffectPenalty],
    ...t.alias.length === 1 ? [m.relation.weakSingleCharacterPenalty] : []
  ], Ie = Ce(
    m.relation.base,
    A,
    ze
  ), le = Object.freeze(
    [C, t.entity, k].filter(
      (z) => z !== null
    )
  ), x = Object.freeze([
    ...t.evidence,
    ...le.filter((z) => z.kind !== "relation").map(
      (z) => Object.freeze({
        kind: "relation-pattern",
        key: `slot:${z.kind}`,
        value: z.value,
        rawRange: Object.freeze({
          start: z.start,
          end: z.end
        }),
        weight: z.confidence
      })
    ),
    ...b !== null ? e.questionCues : e.teachingCues,
    ...s.negated ? e.negationCues : []
  ]), Ne = w === null ? `partial:${t.canonical}:${t.entity.start}` : w.type === "query" ? `query:${w.subject}:${w.relation}` : `statement:${w.subject}:${w.relation}:${w.object}:${w.negated}`;
  return Object.freeze({
    id: `relation-pattern:${Ne}`,
    producer: "relation-pattern",
    producerWeight: m.producerWeight["relation-pattern"],
    result: w,
    concepts: Object.freeze([ss(e, t)]),
    entities: le,
    confidence: Ie,
    evidence: x,
    missingSlots: Object.freeze(W),
    sideEffect: ue
  });
}
function fs(e) {
  var s;
  const t = e.teachingCues.filter(
    ({ key: a }) => a === "teaching:explicit"
  );
  if (t.length === 0 || e.relations.length > 0)
    return null;
  const n = e.concepts.filter(
    ({ id: a }) => a === "teaching"
  ), r = Object.freeze([
    "subject",
    "relation",
    "object"
  ]), i = Ce(
    m.relation.base,
    [],
    r.map(
      () => m.relation.missingSlotPenalty
    )
  ), c = (s = t[0]) == null ? void 0 : s.rawRange;
  return Object.freeze({
    id: `relation-pattern:partial-teaching:${(c == null ? void 0 : c.start) ?? 0}`,
    producer: "relation-pattern",
    producerWeight: m.producerWeight["relation-pattern"],
    result: null,
    concepts: Object.freeze(n),
    entities: Object.freeze([]),
    confidence: i,
    evidence: Object.freeze(t),
    missingSlots: r,
    sideEffect: "none"
  });
}
function ds(e) {
  const t = fs(e);
  return Object.freeze(
    [
      ...e.relations.map(
        (n) => ls(e, n)
      ),
      t
    ].filter(
      (n) => n !== null
    )
  );
}
function ms(e) {
  if (e === null)
    return "partial";
  switch (e.type) {
    case "intent":
      return `intent:${e.intent}:${e.entities.join("|")}`;
    case "statement":
      return `statement:${e.subject}:${e.relation}:${e.object}:${e.negated}`;
    case "query":
      return `query:${e.kind}:${e.subject}:${e.relation}:${e.object ?? ""}`;
    case "unknown":
      return "unknown";
  }
}
function bs(e) {
  const t = e.result === null ? e.id : ms(e.result);
  return [
    e.producer,
    t,
    [...e.missingSlots].sort().join(",")
  ].join("::");
}
function gs(e) {
  var t, n;
  return [
    e.kind,
    e.key,
    e.value ?? "",
    ((t = e.rawRange) == null ? void 0 : t.start) ?? "",
    ((n = e.rawRange) == null ? void 0 : n.end) ?? ""
  ].join(":");
}
function hs(e) {
  var n, r;
  const t = e.evidence[0];
  return [
    e.id,
    ((n = t == null ? void 0 : t.rawRange) == null ? void 0 : n.start) ?? "",
    ((r = t == null ? void 0 : t.rawRange) == null ? void 0 : r.end) ?? ""
  ].join(":");
}
function ps(e) {
  return [
    e.kind,
    e.start,
    e.end,
    e.value
  ].join(":");
}
function Pe(e, t) {
  const n = /* @__PURE__ */ new Set(), r = [];
  for (const i of e) {
    const c = t(i);
    n.has(c) || (n.add(c), r.push(i));
  }
  return Object.freeze(r);
}
function js(e, t) {
  const n = {
    none: 0,
    "memory-write": 1,
    "knowledge-write": 2
  };
  return n[e] >= n[t] ? e : t;
}
function ys(e, t) {
  return Object.freeze({
    id: e.id.localeCompare(t.id) <= 0 ? e.id : t.id,
    producer: e.producer,
    producerWeight: ye(
      Math.max(e.producerWeight, t.producerWeight)
    ),
    result: e.result ?? t.result,
    concepts: Pe(
      [...e.concepts, ...t.concepts],
      hs
    ),
    entities: Pe(
      [...e.entities, ...t.entities],
      ps
    ),
    confidence: ye(
      Math.max(e.confidence, t.confidence)
    ),
    evidence: Pe(
      [...e.evidence, ...t.evidence],
      gs
    ),
    missingSlots: Object.freeze(
      [.../* @__PURE__ */ new Set([...e.missingSlots, ...t.missingSlots])].sort()
    ),
    sideEffect: js(
      e.sideEffect,
      t.sideEffect
    )
  });
}
function Os(e) {
  const t = /* @__PURE__ */ new Map();
  for (const n of e) {
    const r = bs(n), i = t.get(r);
    t.set(
      r,
      i === void 0 ? n : ys(i, n)
    );
  }
  return Object.freeze([...t.values()]);
}
function Es(e) {
  return Object.freeze(
    [...e].sort(
      (t, n) => n.confidence - t.confidence || t.missingSlots.length - n.missingSlots.length || m.producerTieBreak[t.producer] - m.producerTieBreak[n.producer] || t.id.localeCompare(n.id)
    )
  );
}
function Ss(e, t, n) {
  const r = [];
  return e.trim().length === 0 && r.push(
    Object.freeze({
      level: "info",
      code: "semantic.empty-input",
      message: "Input contains no semantic surface content."
    })
  ), t.every(
    (i) => {
      var c;
      return i.producer === "legacy-regex" && ((c = i.result) == null ? void 0 : c.type) === "unknown";
    }
  ) && r.push(
    Object.freeze({
      level: "debug",
      code: "semantic.no-structured-candidate",
      message: "No structured semantic candidate was generated."
    })
  ), n !== void 0 && t.some(({ producer: i }) => i === "context") && r.push(
    Object.freeze({
      level: "debug",
      code: "semantic.context-candidate-generated",
      message: "A bounded context candidate was generated."
    })
  ), Object.freeze(r);
}
function ws(e, t) {
  const n = fc(e), r = Cc(n), i = [
    Vc(r),
    ...Zc(r),
    ...ds(r)
  ], c = t === void 0 ? void 0 : ee(t), s = c === void 0 ? Object.freeze({
    candidates: Object.freeze([]),
    supersededCandidateIds: Object.freeze([])
  }) : Uc(
    r,
    i,
    c
  ), a = new Set(s.supersededCandidateIds), o = [
    ...i.filter(({ id: l }) => !a.has(l)),
    ...s.candidates
  ], d = Es(
    Os(o)
  );
  return Object.freeze({
    input: n,
    extraction: r,
    candidates: d,
    diagnostics: Ss(
      e,
      d,
      c
    )
  });
}
const Cs = /^(?:你好|您好|嗨|哈喽|hello|hi)[,，]\s*/iu;
function sn(e) {
  return e.type === "intent" && e.intent === "RememberName";
}
function an(e) {
  return e.type === "statement" || sn(e);
}
function on(e) {
  var t, n;
  return e.sideEffect !== "none" || ((t = e.result) == null ? void 0 : t.type) === "statement" || ((n = e.result) == null ? void 0 : n.type) === "intent" && e.result.intent === "RememberName";
}
function je(e) {
  return e.trim().replace(/\s+/gu, " ").toLocaleLowerCase("und");
}
function Rs(e, t) {
  let n = je(e.relation), r = je(e.object);
  const i = t.extraction.relations.some(
    ({ conceptId: c }) => c === "is-a"
  );
  return n === "是" && i && (n = "属于"), n === "属于" && r.startsWith("一种") && r.length > 2 && (r = r.slice(2)), n === "指的是" && (n = "意思是"), Object.freeze([
    je(e.subject),
    n,
    r,
    e.negated
  ]);
}
function Je(e, t) {
  if ((e == null ? void 0 : e.type) === "statement")
    return `knowledge:${Rs(e, t).join("|")}`;
  if ((e == null ? void 0 : e.type) === "intent" && e.intent === "RememberName") {
    const n = e.entities[0];
    return n === void 0 ? null : `memory:name:${je(n)}`;
  }
  return null;
}
function ks(e) {
  return e.kind === "accept" ? Object.freeze([
    e.selectedCandidate,
    ...e.secondaryCandidates
  ]) : Object.freeze([]);
}
function zs(e) {
  return new Set(
    e.candidates.filter(on).filter(
      (t) => t.result !== null && t.result.type !== "unknown" && t.missingSlots.length === 0
    ).map(
      (t) => Je(t.result, e)
    ).filter((t) => t !== null)
  );
}
function Is(e) {
  return sn(e) ? e.raw.trim().replace(Cs, "") : e.raw;
}
function P(e) {
  return Object.freeze({
    kind: "block-and-no-understanding",
    reason: e
  });
}
function Ns(e, t, n) {
  if (!an(t))
    return Object.freeze({
      kind: "allow-passive-legacy",
      reason: "not-a-side-effect"
    });
  if (e.kind === "clarify")
    return Object.freeze({
      kind: "block-and-clarify",
      reason: "semantic-clarification-required",
      decision: e
    });
  if (e.kind === "reject-side-effect")
    return P("semantic-side-effect-rejected");
  if (e.kind !== "accept")
    return P("semantic-side-effect-not-accepted");
  if (n.extraction.negationCues.length > 0)
    return P("negation-detected");
  if (n.extraction.questionCues.length > 0)
    return P("question-detected");
  if (Kt(n.input.raw))
    return P("explicit-prohibition");
  if (tt(
    Is(t)
  ))
    return P("unsafe-input-structure");
  const r = ks(
    e
  ).filter(on);
  if (r.length === 0 || r.some(
    (s) => s.result === null || s.missingSlots.length > 0
  ))
    return P(
      r.length === 0 ? "semantic-side-effect-not-accepted" : "missing-required-slot"
    );
  if (zs(n).size > 1)
    return P("compound-or-conflicting-side-effect");
  const i = Je(
    t,
    n
  ), c = new Set(
    r.map(
      (s) => Je(s.result, n)
    ).filter((s) => s !== null)
  );
  return i === null || !c.has(i) ? Object.freeze({
    kind: "reject",
    reason: "side-effect-interpretation-mismatch"
  }) : Object.freeze({
    kind: "allow-legacy-side-effect",
    reason: "semantic-side-effect-confirmed"
  });
}
const Ts = /* @__PURE__ */ new Set([
  "Greeting",
  "Thanks",
  "Farewell",
  "Identity",
  "RecallName"
]), vs = /* @__PURE__ */ new Set([
  "subject",
  "relation",
  "object",
  "name",
  "intent"
]);
function S(e) {
  return e.trim().replace(/\s+/gu, " ").toLocaleLowerCase("und");
}
function un(e) {
  var t, n;
  return e.sideEffect !== "none" || ((t = e.result) == null ? void 0 : t.type) === "statement" || ((n = e.result) == null ? void 0 : n.type) === "intent" && e.result.intent === "RememberName";
}
function As(e) {
  return e.type === "query" || e.type === "intent" && Ts.has(e.intent);
}
function ln(e, t) {
  if (e.type !== t.type) return !1;
  switch (e.type) {
    case "intent":
      return t.type !== "intent" ? !1 : e.intent === t.intent && e.entities.length === t.entities.length && e.entities.every(
        (n, r) => S(n) === S(t.entities[r] ?? "")
      );
    case "query":
      return t.type === "query" && e.kind === t.kind && S(e.subject) === S(t.subject) && S(e.relation) === S(t.relation) && S(e.object ?? "") === S(t.object ?? "") && e.explain === t.explain;
    case "statement":
      return t.type === "statement" && S(e.subject) === S(t.subject) && S(e.relation) === S(t.relation) && S(e.object) === S(t.object) && e.negated === t.negated;
    case "unknown":
      return t.type === "unknown";
  }
}
function xs(e, t) {
  const n = e.result;
  return e.producer !== "context" || (n == null ? void 0 : n.type) !== "query" ? !1 : t.type === "intent" && t.intent === "Identity" ? n.relation === "意思是" || e.concepts.some(({ id: r }) => r === "context-ellipsis") : t.type !== "query" || !ct(t.subject) && !st(t.subject) ? !1 : S(n.relation) === S(t.relation) && n.kind === t.kind && S(n.object ?? "") === S(t.object ?? "");
}
function Ls(e) {
  const t = e.result;
  if ((t == null ? void 0 : t.type) === "intent")
    switch (t.intent) {
      case "Greeting":
        return "greeting";
      case "Thanks":
        return "thanks";
      case "Farewell":
        return "farewell";
      case "Identity":
        return "identity";
      case "RecallName":
        return "recall-name";
      case "RememberName":
        return "remember-name";
    }
  return (t == null ? void 0 : t.type) === "query" ? "query" : (t == null ? void 0 : t.type) === "statement" || e.concepts.some(({ id: n }) => n === "teaching") ? "teaching" : "unknown";
}
function $s(e) {
  var n;
  const t = e == null ? void 0 : e.result;
  return (t == null ? void 0 : t.type) === "query" || (t == null ? void 0 : t.type) === "statement" ? t.relation : (n = e == null ? void 0 : e.entities.find(({ kind: r }) => r === "relation")) == null ? void 0 : n.value;
}
function _s(e) {
  return e.clarificationKind === "ambiguous-intent" || e.clarificationKind === "conflicting-candidates" ? "ambiguous" : e.clarificationKind === "uncertain-name" || e.clarificationKind === "uncertain-teaching" ? "uncertain" : "missing-information";
}
function fn(e) {
  const t = Object.freeze(
    [...new Set(e.missingSlots)].filter(
      (c) => vs.has(c)
    ).sort()
  ), n = Object.freeze(
    [...new Set(e.candidateOptions.map(Ls))].sort()
  ), r = Object.freeze(
    [
      ...new Set(
        e.candidateOptions.flatMap(
          ({ entities: c }) => c.filter(
            ({ source: s, kind: a }) => s === "context" && (a === "subject" || a === "self")
          ).map(({ value: s }) => s)
        )
      )
    ].filter((c) => c.length > 0 && c.length <= 80).slice(0, 3)
  ), i = $s(e.candidateOptions[0]);
  return Object.freeze({
    clarificationKind: e.clarificationKind,
    missingSlots: t,
    candidateLabels: n,
    reasonCategory: _s(e),
    ...i === void 0 ? {} : { relation: i },
    ...r.length === 0 ? {} : { contextLabels: r }
  });
}
function Ks(e, t) {
  return t.type === "unknown" || t.type === "query" && ct(t.subject) && e.missingSlots.includes("subject") && e.candidateOptions.some(
    ({ producer: n }) => n === "context"
  ) || e.reasonCodes.includes("compound-query") && e.candidateOptions.length >= 2 && e.candidateOptions.every(
    (n) => !un(n)
  ) ? !0 : t.type === "statement" && e.missingSlots.includes("object") && /^(?:吗|呢|什么|啥|\?)$/u.test(t.object.trim()) && e.candidateOptions.some(
    (n) => n.evidence.some(({ kind: r }) => r === "question-cue")
  );
}
function Xe(e, t) {
  return Object.freeze({
    kind: "no-understanding",
    failure: Object.freeze({
      type: "unknown",
      raw: e.raw,
      reason: t
    })
  });
}
function Ms(e, t) {
  switch (e.kind) {
    case "allow-passive-legacy":
      return null;
    case "allow-legacy-side-effect":
      return Object.freeze({
        kind: "fallback-legacy",
        result: t,
        reason: "side-effect-prohibited"
      });
    case "block-and-clarify":
      return Object.freeze({
        kind: "clarification",
        context: fn(e.decision)
      });
    case "block-and-no-understanding":
      return Xe(
        t,
        `legacy-side-effect-blocked:${e.reason}`
      );
    case "reject":
      return Xe(
        t,
        `legacy-side-effect-rejected:${e.reason}`
      );
  }
}
function Ps(e, t, n) {
  const r = Ms(
    Ns(
      e,
      t,
      n
    ),
    t
  );
  if (r !== null) return r;
  switch (e.kind) {
    case "accept": {
      if ([
        e.selectedCandidate,
        ...e.secondaryCandidates
      ].some(un))
        return Object.freeze({
          kind: "fallback-legacy",
          result: t,
          reason: "side-effect-prohibited"
        });
      const c = e.selectedCandidate.result;
      return c === null || c.type === "unknown" ? Object.freeze({
        kind: "fallback-legacy",
        result: t,
        reason: "incomplete-result"
      }) : e.selectedCandidate.missingSlots.length > 0 || !As(c) ? Object.freeze({
        kind: "fallback-legacy",
        result: t,
        reason: "unsupported-result"
      }) : t.type !== "unknown" && !ln(c, t) && !xs(
        e.selectedCandidate,
        t
      ) ? Object.freeze({
        kind: "fallback-legacy",
        result: t,
        reason: "legacy-conflict"
      }) : Object.freeze({ kind: "adopt", result: c });
    }
    case "clarify":
      return Ks(e, t) ? Object.freeze({
        kind: "clarification",
        context: fn(e)
      }) : Object.freeze({
        kind: "fallback-legacy",
        result: t,
        reason: "legacy-conflict"
      });
    case "reject-side-effect":
      return t.type === "unknown" ? Xe(
        t,
        "semantic-side-effect-rejected"
      ) : Object.freeze({
        kind: "fallback-legacy",
        result: t,
        reason: "side-effect-rejected"
      });
    case "no-understanding":
      return t.type === "unknown" ? Object.freeze({
        kind: "no-understanding",
        failure: t
      }) : Object.freeze({
        kind: "fallback-legacy",
        result: t,
        reason: "legacy-conflict"
      });
  }
}
function Ds(e) {
  switch (e.kind) {
    case "accept":
      return e.selectedCandidate;
    case "clarify":
      return e.candidateOptions[0];
    case "reject-side-effect":
      return e.rejectedCandidate;
    case "no-understanding":
      return;
  }
}
function Us(e) {
  var t;
  return e === void 0 ? null : ((t = e.result) == null ? void 0 : t.type) ?? "partial";
}
function qs(e) {
  if (e === void 0) return null;
  const t = e.result;
  return (t == null ? void 0 : t.type) === "intent" ? `semantic:${e.producer}:intent:${t.intent}` : `semantic:${e.producer}:${(t == null ? void 0 : t.type) ?? "partial"}`;
}
function Bs(e) {
  return Object.freeze([...e.reasonCodes]);
}
function Fs(e, t) {
  return e.kind === "accept" ? e.confidence : (t == null ? void 0 : t.confidence) ?? null;
}
function Ws(e, t, n, r) {
  const i = Ds(n), c = (i == null ? void 0 : i.result) === void 0 || i.result === null ? !1 : ln(i.result, t), s = e === "passive" && r.kind !== "fallback-legacy";
  return Object.freeze({
    mode: e,
    legacyType: t.type,
    decisionType: n.kind,
    selectedCandidateId: qs(i),
    selectedCandidateType: Us(i),
    confidence: Fs(n, i),
    reasonCodes: Bs(n),
    equivalentToLegacy: c,
    semanticAdopted: s,
    fellBackToLegacy: e === "shadow" || r.kind === "fallback-legacy",
    adapterKind: r.kind,
    semanticError: !1
  });
}
function Vs(e, t) {
  return Object.freeze({
    mode: e,
    legacyType: t.type,
    decisionType: "error",
    selectedCandidateId: null,
    selectedCandidateType: null,
    confidence: null,
    reasonCodes: Object.freeze([]),
    equivalentToLegacy: !1,
    semanticAdopted: !1,
    fellBackToLegacy: !0,
    adapterKind: "error",
    semanticError: !0
  });
}
const Gs = Object.freeze({
  passiveIntentAcceptThreshold: v(0.72),
  queryAcceptThreshold: v(0.74),
  sideEffectAcceptThreshold: v(0.82),
  minimumCandidateMargin: v(0.08),
  partialCandidateThreshold: v(0.35),
  maximumAlternatives: 3,
  minimumSideEffectEvidenceUnits: 2,
  weakAliasMaximumLength: 1,
  missingSlotPolicy: Object.freeze({
    partialDecision: "clarify",
    sideEffectDecision: "reject-side-effect",
    clarifyExplicitTeaching: !0
  }),
  negationPolicy: Object.freeze({
    preserveNegatedCandidate: !0,
    rejectNegatedSideEffects: !0
  })
}), dn = /* @__PURE__ */ new Set(["Greeting", "Thanks", "Farewell"]), Ys = /* @__PURE__ */ new Set([
  "Greeting+Identity",
  "Greeting+RememberName",
  "Farewell+Thanks"
]), Qs = Object.freeze({
  "threshold-met": 0,
  "corroborated-producers": 1,
  "compatible-secondary-candidate": 2,
  "partial-candidate": 3,
  "missing-required-slot": 4,
  "insufficient-confidence": 5,
  "insufficient-margin": 6,
  "conflicting-candidates": 7,
  "compound-query": 8,
  "side-effect-evidence-insufficient": 9,
  "negation-conflict": 10,
  "no-viable-candidate": 11
}), Hs = Object.freeze({
  "confidence-threshold": 0,
  "candidate-margin": 1,
  "complete-slots": 2,
  "explicit-name": 3,
  "complete-triple": 4,
  "strong-non-alias-evidence": 5,
  "non-question-assertion": 6,
  "non-negated-assertion": 7
});
function mn(e, t) {
  return Object.freeze(
    [...new Set(e)].sort(
      (n, r) => t[n] - t[r] || n.localeCompare(r)
    )
  );
}
function F(e) {
  return mn(e, Qs);
}
function bn(e) {
  return mn(e, Hs);
}
function Z(e) {
  return e.trim().replace(/\s+/gu, " ").toLocaleLowerCase("und");
}
function Js(e) {
  return e.extraction.relations.some(
    ({ conceptId: t }) => t === "is-a"
  );
}
function Ze(e, t) {
  return Js(e) && (t === "是" || t === "属于") ? "属于" : t;
}
function Tt(e, t, n) {
  const r = Z(n);
  return Ze(e, t) === "属于" && r.startsWith("一种") && r.length > 2 ? r.slice(2) : r;
}
function Xs(e, t) {
  const n = t.result;
  if (n === null)
    return `partial:${t.id}`;
  switch (n.type) {
    case "intent":
      return [
        "intent",
        n.intent,
        ...n.entities.map(Z)
      ].join(":");
    case "statement":
      return [
        "statement",
        Z(n.subject),
        Ze(e, n.relation),
        Tt(e, n.relation, n.object),
        n.negated
      ].join(":");
    case "query":
      return [
        "query",
        n.kind,
        Z(n.subject),
        Ze(e, n.relation),
        n.object === void 0 ? "" : Tt(
          e,
          n.relation,
          n.object
        )
      ].join(":");
    case "unknown":
      return `unknown:${t.id}`;
  }
}
function et(e) {
  const t = new Set(
    e.entities.map(
      ({ kind: n, start: r, end: i, value: c }) => `${n}:${r}:${i}:${c}`
    )
  );
  return e.evidence.length + t.size;
}
function U(e) {
  var t, n;
  return ((t = e.result) == null ? void 0 : t.type) === "intent" && e.result.intent === "RememberName" ? "memory-write" : ((n = e.result) == null ? void 0 : n.type) === "statement" ? "knowledge-write" : e.sideEffect;
}
function re(e, t) {
  const n = U(e) === e.sideEffect ? 0 : 1, r = U(t) === t.sideEffect ? 0 : 1;
  return n - r || t.confidence - e.confidence || et(t) - et(e) || e.missingSlots.length - t.missingSlots.length || m.producerTieBreak[e.producer] - m.producerTieBreak[t.producer] || e.id.localeCompare(t.id);
}
function Zs(e, t) {
  const n = /* @__PURE__ */ new Map(), r = [...t].sort(re);
  for (const i of r) {
    const c = Xs(e, i), s = n.get(c);
    s === void 0 ? n.set(c, [i]) : s.push(i);
  }
  return Object.freeze(
    [...n.entries()].map(([i, c]) => {
      const s = Object.freeze(
        [...c].sort(re)
      );
      return Object.freeze({
        key: i,
        representative: s[0],
        supporters: s
      });
    }).sort(
      (i, c) => re(
        i.representative,
        c.representative
      )
    )
  );
}
function ea(e, t) {
  if (U(e) !== "none")
    return t.sideEffectAcceptThreshold;
  const n = e.result;
  return (n == null ? void 0 : n.type) === "intent" && dn.has(n.intent) ? t.passiveIntentAcceptThreshold : (n == null ? void 0 : n.type) === "query" || (n == null ? void 0 : n.type) === "intent" && (n.intent === "Identity" || n.intent === "RecallName") ? t.queryAcceptThreshold : t.partialCandidateThreshold;
}
function ot(e) {
  var t;
  return ((t = e.result) == null ? void 0 : t.type) === "statement" && e.result.negated;
}
function ta(e) {
  var n;
  if (((n = e.result) == null ? void 0 : n.type) !== "intent" || e.result.intent !== "RememberName")
    return !1;
  const t = e.result.entities[0];
  return t === void 0 ? !1 : e.entities.some(
    (r) => r.kind === "person-name" && Z(r.value) === Z(t)
  );
}
function na(e) {
  const t = e.result;
  return (t == null ? void 0 : t.type) === "statement" && t.subject.trim().length > 0 && t.relation.trim().length > 0 && t.object.trim().length > 0;
}
function ra(e, t) {
  const n = /* @__PURE__ */ new Set([
    "legacy-regex",
    "relation-pattern",
    "entity-pattern",
    "teaching-cue"
  ]);
  return e.evidence.some(({ kind: i }) => n.has(i)) ? !0 : !(e.evidence.length > 0 && e.evidence.every(
    ({ kind: i, value: c }) => i === "lexicon-alias" && ((c == null ? void 0 : c.length) ?? 0) <= t.weakAliasMaximumLength
  )) && et(e) >= t.minimumSideEffectEvidenceUnits;
}
function gn(e, t, n) {
  var s;
  const r = U(e);
  if (r === "none")
    return Object.freeze({
      safe: !0,
      requiredEvidence: Object.freeze([]),
      reasonCodes: Object.freeze([])
    });
  const i = [], c = [];
  return (e.missingSlots.length > 0 || e.result === null) && (i.push("complete-slots"), c.push("missing-required-slot")), e.confidence < n.sideEffectAcceptThreshold && (i.push("confidence-threshold"), c.push("insufficient-confidence")), n.negationPolicy.rejectNegatedSideEffects && ot(e) && (i.push("non-negated-assertion"), c.push("negation-conflict")), ((s = e.result) == null ? void 0 : s.type) === "statement" && t.extraction.questionCues.length > 0 && (i.push("non-question-assertion"), c.push("side-effect-evidence-insufficient")), r === "memory-write" && !ta(e) && (i.push("explicit-name"), c.push("side-effect-evidence-insufficient")), r === "knowledge-write" && !na(e) && (i.push("complete-triple"), c.push("side-effect-evidence-insufficient")), ra(e, n) || (i.push("strong-non-alias-evidence"), c.push("side-effect-evidence-insufficient")), Object.freeze({
    safe: i.length === 0,
    requiredEvidence: bn(i),
    reasonCodes: F(c)
  });
}
function ia(e) {
  return e.result !== null && e.result.type !== "unknown" && e.missingSlots.length === 0;
}
function ca(e, t, n) {
  return ot(e) && !n.negationPolicy.preserveNegatedCandidate ? !1 : ia(e) && e.confidence >= ea(e, n) && gn(e, t, n).safe;
}
function sa(e, t) {
  const n = e.candidates.filter(
    (r) => ca(r, e, t)
  );
  return Zs(e, n);
}
function vt(e) {
  var t;
  return ((t = e.result) == null ? void 0 : t.type) === "intent" ? e.result.intent : null;
}
function At(e, t) {
  const n = vt(e), r = vt(t);
  if (n === null || r === null)
    return !1;
  const i = [n, r].sort().join("+");
  return Ys.has(i);
}
function hn(e) {
  const t = e.result;
  return (t == null ? void 0 : t.type) === "query" || (t == null ? void 0 : t.type) === "intent" && (t.intent === "Identity" || t.intent === "RecallName");
}
function aa(e) {
  var t;
  return U(e) !== "none" ? "high" : hn(e) ? "low" : ((t = e.result) == null ? void 0 : t.type) === "intent" && dn.has(e.result.intent) ? "none" : "medium";
}
function De(e, t) {
  return Object.freeze(
    e.slice(0, t.maximumAlternatives).map(({ representative: n }) => n)
  );
}
function oa(e) {
  return e.concepts.some(({ id: t }) => t === "remember-name") ? "uncertain-name" : e.concepts.some(({ id: t }) => t === "teaching") && e.missingSlots.length > 1 ? "uncertain-teaching" : e.missingSlots.includes("relation") ? "missing-relation" : e.missingSlots.includes("subject") ? "missing-subject" : e.missingSlots.includes("object") ? "missing-object" : "ambiguous-intent";
}
function ua(e) {
  return e.result === null && e.concepts.some(({ id: t }) => t === "teaching");
}
function la(e, t) {
  if (t.missingSlotPolicy.partialDecision !== "clarify")
    return null;
  const n = e.candidates.filter(
    (i) => i.result === null || i.missingSlots.length > 0
  ).filter(
    (i) => U(i) === "none" && (i.confidence >= t.partialCandidateThreshold || t.missingSlotPolicy.clarifyExplicitTeaching && ua(i))
  ).sort(re), r = n[0];
  return r === void 0 ? null : Object.freeze({
    kind: "clarify",
    candidateOptions: Object.freeze(
      n.slice(0, t.maximumAlternatives)
    ),
    missingSlots: Object.freeze([...r.missingSlots]),
    clarificationKind: oa(r),
    reasonCodes: F([
      "partial-candidate",
      "missing-required-slot",
      ...r.confidence < t.partialCandidateThreshold ? ["insufficient-confidence"] : []
    ])
  });
}
function fa(e, t) {
  const r = e.candidates.filter((i) => U(i) !== "none").filter(
    (i) => !ot(i) || t.negationPolicy.preserveNegatedCandidate
  ).map(
    (i) => Object.freeze({
      candidate: i,
      assessment: gn(i, e, t)
    })
  ).filter(({ assessment: i }) => !i.safe).sort(
    (i, c) => re(i.candidate, c.candidate)
  )[0];
  return r === void 0 ? null : Object.freeze({
    kind: "reject-side-effect",
    rejectedCandidate: r.candidate,
    requiredEvidence: r.assessment.requiredEvidence,
    reasonCodes: r.assessment.reasonCodes
  });
}
function da(e) {
  return Object.freeze({
    count: e.diagnostics.length,
    codes: Object.freeze(
      [...new Set(e.diagnostics.map(({ code: t }) => t))].sort()
    )
  });
}
function ma(e, t = Gs) {
  const n = sa(e, t), r = n.filter(
    ({ representative: b }) => hn(b)
  );
  if (e.extraction.questionCues.length >= 2 && r.length >= 2)
    return Object.freeze({
      kind: "clarify",
      candidateOptions: De(r, t),
      missingSlots: Object.freeze([]),
      clarificationKind: "ambiguous-intent",
      reasonCodes: F([
        "compound-query",
        "conflicting-candidates"
      ])
    });
  const i = n[0];
  if (i === void 0) {
    const b = la(e, t);
    if (b !== null)
      return b;
    const g = fa(
      e,
      t
    );
    if (g !== null)
      return g;
    const C = e.candidates.some(
      (k) => k.result !== null && k.result.type !== "unknown"
    );
    return Object.freeze({
      kind: "no-understanding",
      diagnosticsSummary: da(e),
      reasonCodes: F([
        ...C ? ["insufficient-confidence"] : [],
        "no-viable-candidate"
      ])
    });
  }
  const c = i.representative, s = n.slice(1).filter(
    ({ representative: b }) => At(c, b)
  ), a = n.slice(1).filter(
    ({ representative: b }) => !At(c, b)
  ), o = a[0];
  if (o !== void 0 && c.confidence - o.representative.confidence < t.minimumCandidateMargin)
    return U(c) !== "none" ? Object.freeze({
      kind: "reject-side-effect",
      rejectedCandidate: c,
      requiredEvidence: bn(["candidate-margin"]),
      reasonCodes: F([
        "insufficient-margin",
        "conflicting-candidates"
      ])
    }) : Object.freeze({
      kind: "clarify",
      candidateOptions: De(
        [i, o],
        t
      ),
      missingSlots: Object.freeze([]),
      clarificationKind: "conflicting-candidates",
      reasonCodes: F([
        "insufficient-margin",
        "conflicting-candidates"
      ])
    });
  const d = Object.freeze(
    s.slice(0, t.maximumAlternatives).map(({ representative: b }) => b)
  ), l = De(
    a,
    t
  );
  return Object.freeze({
    kind: "accept",
    selectedCandidate: c,
    secondaryCandidates: d,
    confidence: v(c.confidence),
    reasonCodes: F([
      "threshold-met",
      ...i.supporters.length > 1 ? ["corroborated-producers"] : [],
      ...d.length > 0 ? ["compatible-secondary-candidate"] : []
    ]),
    alternatives: l,
    riskLevel: aa(c)
  });
}
const ba = {
  identity: p.Is,
  capability: p.Can,
  creator: Lt
};
function ga(e) {
  return e === "identity" || e === "capability" || e === "creator";
}
const ha = /* @__PURE__ */ new Set([
  "属于",
  "是",
  "会",
  "喜欢",
  "在",
  "有",
  "意思是",
  "开发者",
  "none",
  "unknown"
]);
function he(e) {
  return e === void 0 || e.length === 0 ? "none" : ha.has(
    e
  ) ? e : "unknown";
}
function pa() {
  var e;
  try {
    const t = (e = globalThis.performance) == null ? void 0 : e.now();
    return typeof t == "number" && Number.isFinite(t) ? t : null;
  } catch {
    return null;
  }
}
function pe(e, t) {
  return e === null || t === null || !Number.isFinite(e) || !Number.isFinite(t) || t < e ? null : t - e;
}
function pn(e) {
  switch (e.kind) {
    case "accept":
      return [
        e.selectedCandidate,
        ...e.secondaryCandidates
      ];
    case "clarify":
      return e.candidateOptions;
    case "reject-side-effect":
      return [e.rejectedCandidate];
    case "no-understanding":
      return [];
  }
}
function Ue(e, t, n) {
  return Object.freeze({
    negatedInput: e.extraction.negationCues.length > 0,
    contextResolved: n && pn(t).some(
      ({ producer: r }) => r === "context"
    )
  });
}
function ja(e) {
  switch (e) {
    case "missing-subject":
      return "missing-subject";
    case "missing-relation":
      return "missing-relation";
    case "missing-object":
      return "missing-object";
    case "ambiguous-intent":
      return "ambiguous-intent";
    case "conflicting-candidates":
      return "conflicting-candidates";
    case "uncertain-name":
    case "uncertain-teaching":
      return "insufficient-evidence";
    case "none":
      return "unclassified";
  }
}
function ya(e) {
  return {
    startedAt: e,
    resultCategory: "safe-fallback",
    reasonCategory: "unclassified",
    relationCategory: "none",
    semanticAdopted: !1,
    legacyFallback: !1,
    contextUsed: !1,
    clarificationKind: "none",
    reasonerPathLength: 0,
    semanticDurationMs: null,
    reasonerDurationMs: null,
    queriedRelation: "none",
    alternativeKnownRelation: "none",
    alignmentResult: "unavailable",
    classificationLocked: !1
  };
}
function Oa(e, t) {
  const [n = Q, r] = e.entities, i = ga(r) ? r : "identity", c = ba[i], s = t.match({ subject: n, relation: c });
  return { kind: "identity", aspect: i, subject: n, facts: s, raw: e.raw };
}
function Ea(e, t) {
  const [n] = e.entities, r = t.remember(ie.Name, n ?? "");
  return { kind: "remembered", key: r.key, value: r.value, raw: e.raw };
}
function Sa(e, t) {
  const n = t.recall(ie.Name);
  return { kind: "recalled", key: ie.Name, value: (n == null ? void 0 : n.value) ?? null, raw: e.raw };
}
function wa(e, t, n) {
  switch (e.intent) {
    case "Greeting":
      return { kind: "greeting", raw: e.raw };
    case "Thanks":
      return { kind: "thanks", raw: e.raw };
    case "Farewell":
      return { kind: "farewell", raw: e.raw };
    case "Identity":
      return Oa(e, t);
    case "RememberName":
      return Ea(e, n);
    case "RecallName":
      return Sa(e, n);
    default: {
      const r = e.intent;
      throw new Error(`createSunlandEngine: unhandled intent "${String(r)}"`);
    }
  }
}
function Ia(e = {}) {
  var ut, lt, ft, dt;
  const t = e.knowledgeStore ?? xn(), n = e.memory ?? Mn(), r = ji(e.personalityId), i = e.parser ?? Pt(), c = e.storage, s = e.semanticMode ?? "passive", a = e.semanticContextMode ?? "off", o = e.semanticDebug === !0, d = ((ut = e.semanticRuntime) == null ? void 0 : ut.analyze) ?? ws, l = ((lt = e.semanticRuntime) == null ? void 0 : lt.plan) ?? ma, b = ((ft = e.observationRuntime) == null ? void 0 : ft.now) ?? pa, g = ((dt = e.observationRuntime) == null ? void 0 : dt.finalizeSummary) ?? ((f) => f);
  let C = null;
  const k = An(), w = c ? `${c.key}::memory` : void 0;
  c && Nn(t, c.adapter, c.key), w && c && Kn(n, c.adapter, w), e.seedDemoData === !0 && t.all().length === 0 && zn(t);
  function W() {
    c && In(t, c.adapter, c.key);
  }
  function ue() {
    c && w && _n(n, c.adapter, w);
  }
  function A() {
    try {
      const f = b();
      return typeof f == "number" && Number.isFinite(f) ? f : null;
    } catch {
      return null;
    }
  }
  function ze(f, j) {
    if ((f.type === "query" || f.type === "statement") && (j.relationCategory = he(
      f.relation
    )), f.type === "query" && (j.queriedRelation = he(
      f.relation
    )), !j.classificationLocked) {
      if (f.type === "unknown") {
        j.resultCategory = "no-understanding", j.reasonCategory = "unknown-safe-fallback";
        return;
      }
      j.resultCategory = "understood", j.reasonCategory = j.semanticAdopted ? "complete-passive-understanding" : "unclassified";
    }
  }
  function Ie(f, j, u) {
    if (f.semanticAdopted = s === "passive" && u.kind !== "fallback-legacy", f.legacyFallback = s === "shadow" || u.kind === "fallback-legacy", f.contextUsed = u.kind !== "fallback-legacy" && pn(j).some(
      ({ producer: y }) => y === "context"
    ), u.kind === "clarification") {
      f.clarificationKind = u.context.clarificationKind, u.context.clarificationKind === "missing-subject" && f.contextUsed ? (f.resultCategory = "context-unresolved", f.reasonCategory = "unresolved-context") : (f.resultCategory = "clarification", f.reasonCategory = ja(
        u.context.clarificationKind
      )), f.classificationLocked = !0;
      return;
    }
    u.kind === "no-understanding" && (u.failure.reason.startsWith(
      "legacy-side-effect-blocked:"
    ) || u.failure.reason.startsWith(
      "legacy-side-effect-rejected:"
    ) || u.failure.reason === "semantic-side-effect-rejected" ? (f.resultCategory = "side-effect-blocked", f.reasonCategory = "blocked-side-effect") : (f.resultCategory = "no-understanding", f.reasonCategory = "unknown-safe-fallback"), f.classificationLocked = !0);
  }
  function le(f, j, u, y) {
    if (y.relationCategory = he(
      f.relation
    ), y.queriedRelation = y.relationCategory, y.alternativeKnownRelation = u.mode === "fallback" && j.length > 0 ? he(u.matchedRelation) : "none", j.length === 0) {
      y.reasonerPathLength = 0, y.classificationLocked || (y.resultCategory = "missing-knowledge", y.reasonCategory = "missing-knowledge"), y.alignmentResult = u.mode === "fallback" ? "no-alternative-known" : "unavailable";
      return;
    }
    y.reasonerPathLength = j.reduce(
      (V, B) => Math.max(V, Math.max(1, B.path.length - 1)),
      1
    ), y.alignmentResult = "aligned";
  }
  function x(f, j, u = {}) {
    switch (j !== void 0 && ze(f, j), f.type) {
      case "statement": {
        const y = t.add(
          { subject: f.subject, relation: f.relation, object: f.object, negated: f.negated },
          { source: "user" }
        );
        return W(), r.respond({ kind: "learned", record: y });
      }
      case "query": {
        const y = f.subject.trim().toLocaleLowerCase("und") === Q.toLocaleLowerCase("und") ? k : t, V = j === void 0 ? null : A(), B = $i(
          f,
          y,
          u
        ), L = B.result;
        j !== void 0 && (j.reasonerDurationMs = pe(
          V,
          A()
        ), le(
          f,
          L.answers,
          B.relationResolution,
          j
        ));
        const fe = yt.plan(L);
        return r.respond({ kind: "reasoning-result", result: L, plan: fe });
      }
      case "intent": {
        const y = wa(f, k, n);
        return f.intent === "RememberName" && ue(), r.respond(y);
      }
      case "unknown":
        return r.respond({ kind: "unknown-input", failure: f });
      default: {
        const y = f;
        throw new Error(`createSunlandEngine: unhandled parse result ${JSON.stringify(y)}`);
      }
    }
  }
  function Ne(f) {
    const j = yt.planClarification(f);
    return r.respond({ kind: "clarification", plan: j });
  }
  function z(f, j = {}) {
    const u = j.observationMode === "summary" ? ya(A()) : void 0, y = ee(a === "enabled" ? j.semanticContext : j.semanticContext ?? Xt()), V = () => Object.freeze({
      kind: "none",
      baseVersion: y.version
    }), B = (R) => {
      if (u === void 0) return R;
      try {
        let ne = null;
        try {
          const ve = t.all().length;
          ne = Number.isSafeInteger(ve) && ve >= 0 ? ve : null;
        } catch {
          ne = null;
        }
        const Te = {
          resultCategory: u.resultCategory,
          reasonCategory: u.reasonCategory,
          relationCategory: u.relationCategory,
          semanticAdopted: u.semanticAdopted,
          legacyFallback: u.legacyFallback,
          contextUsed: u.contextUsed,
          clarificationKind: u.clarificationKind,
          reasonerPathLength: u.reasonerPathLength,
          knowledgeCount: ne,
          totalDurationMs: pe(
            u.startedAt,
            A()
          ),
          semanticDurationMs: u.semanticDurationMs,
          reasonerDurationMs: u.reasonerDurationMs,
          queriedRelation: u.queriedRelation,
          alternativeKnownRelation: u.alternativeKnownRelation,
          alignmentResult: u.alignmentResult
        }, Y = Ji(Te), de = Zi(
          g(Y)
        );
        return de === null ? R : Object.freeze({
          response: R.response,
          semanticContextUpdate: R.semanticContextUpdate,
          observationSummary: de
        });
      } catch {
        return R;
      }
    }, L = (R) => B(
      Object.freeze({
        response: R,
        semanticContextUpdate: V()
      })
    ), fe = (R, ne, Te) => {
      let Y = a === "enabled";
      if (Y && j.canCommitSemanticContext !== void 0)
        try {
          Y = j.canCommitSemanticContext();
        } catch {
          Y = !1;
        }
      const de = s === "passive" ? Lc({
        context: y,
        decision: ne,
        executedResult: Te,
        turnId: j.turnId ?? `turn-${y.version + 1}`,
        canCommit: Y
      }) : V();
      return B(
        Object.freeze({ response: R, semanticContextUpdate: de })
      );
    }, M = i.parse(f);
    if (C = null, s === "off")
      return u !== void 0 && (u.legacyFallback = !0), L(
        x(M, u)
      );
    let G, $, N;
    const mt = u === void 0 ? null : A();
    try {
      G = d(
        f,
        a === "enabled" ? y : void 0
      ), $ = l(
        G,
        e.understandingPolicy
      ), N = Ps(
        $,
        M,
        G
      ), u !== void 0 && (u.semanticDurationMs = pe(
        mt,
        A()
      ), Ie(
        u,
        $,
        N
      )), o && (C = Ws(
        s,
        M,
        $,
        N
      ));
    } catch {
      u !== void 0 && (u.semanticDurationMs = pe(
        mt,
        A()
      ), u.semanticAdopted = !1, u.legacyFallback = !0), o && (C = Vs(
        s,
        M
      ));
      const R = an(M) ? x({
        type: "unknown",
        raw: M.raw,
        reason: "semantic-side-effect-validation-unavailable"
      }, u) : x(M, u, {
        negatedInput: !0
      });
      return u !== void 0 && (u.resultCategory = "safe-fallback", u.reasonCategory = "semantic-runtime", u.classificationLocked = !0), L(R);
    }
    if (s === "shadow")
      return L(
        x(
          M,
          u,
          Ue(
            G,
            $,
            !1
          )
        )
      );
    switch (N.kind) {
      case "adopt":
        return fe(
          x(
            N.result,
            u,
            Ue(
              G,
              $,
              !0
            )
          ),
          $,
          N.result
        );
      case "clarification":
        return L(
          Ne(N.context)
        );
      case "no-understanding":
        return L(
          x(N.failure, u)
        );
      case "fallback-legacy":
        return fe(
          x(
            N.result,
            u,
            Ue(
              G,
              $,
              !1
            )
          ),
          $,
          N.result
        );
      default: {
        const R = N;
        throw new Error(
          `createSunlandEngine: unhandled semantic adaptation ${JSON.stringify(R)}`
        );
      }
    }
  }
  return {
    knowledgeStore: t,
    memory: n,
    semanticMode: s,
    semanticContextMode: a,
    getLastSemanticShadow() {
      return o ? C : null;
    },
    respond(f) {
      return z(f).response;
    },
    process: z
  };
}
function Na() {
  const e = /* @__PURE__ */ new Map();
  return {
    getItem(t) {
      return e.get(t) ?? null;
    },
    setItem(t, n) {
      e.set(t, n);
    },
    removeItem(t) {
      e.delete(t);
    }
  };
}
export {
  Ft as CONTEXT_SCHEMA_VERSION,
  Lt as CREATOR_RELATION,
  hi as DEFAULT_PERSONALITY_ID,
  qi as DURATION_BUCKETS,
  Wn as FAREWELL_PHRASES,
  Tn as FROST_SUBJECT,
  We as FrostPersonality,
  Un as GREETING_PHRASES,
  xt as InMemoryKnowledgeStore,
  Bi as KNOWLEDGE_COUNT_BUCKETS,
  qe as LEGACY_SIDE_EFFECT_LIMITS,
  Ui as OBSERVATION_CLARIFICATION_KINDS,
  Pi as OBSERVATION_REASON_CATEGORIES,
  Di as OBSERVATION_RELATION_CATEGORIES,
  Mi as OBSERVATION_RESULT_CATEGORIES,
  Wt as OBSERVATION_SCHEMA_VERSION,
  jt as PlainPersonality,
  Fi as REASONER_PATH_BUCKETS,
  er as RECALL_NAME_PHRASES,
  Wi as RELATION_ALIGNMENT_RESULTS,
  Tr as RegexParser,
  Bt as SEMANTIC_SCHEMA_VERSION,
  qt as SUNLAND_CORE_VERSION,
  Q as SUNLAND_SUBJECT,
  Bn as THANKS_PHRASES,
  za as applySemanticContextUpdate,
  $e as bucketDuration,
  _i as bucketKnowledgeCount,
  Ki as bucketReasonerPath,
  Mt as countKnownRelationMentions,
  Xt as createEmptySemanticContext,
  Vn as createFarewellIntentMatcher,
  qn as createGreetingIntentMatcher,
  Zn as createIdentityIntentMatcher,
  Se as createKeywordIntentMatcher,
  xn as createKnowledgeStore,
  kr as createLocatePattern,
  Na as createMemoryStorageAdapter,
  Sr as createObjectOfPattern,
  Ji as createObservationSummary,
  Pt as createParser,
  tr as createRecallNameIntentMatcher,
  hr as createRememberNameIntentMatcher,
  An as createSelfKnowledgeStore,
  Fe as createStatementPattern,
  Ia as createSunlandEngine,
  Fn as createThanksIntentMatcher,
  Cr as createVerifyPattern,
  zr as createWhyPattern,
  pr as defaultIntentMatchers,
  Nr as defaultPatterns,
  ji as getPersonality,
  _t as hasChoiceOrSequenceStructure,
  Kt as hasExplicitSideEffectProhibition,
  or as hasInternalClauseBoundary,
  ur as hasQuestionStructure,
  tt as hasUnsafeLegacySideEffectStructure,
  ka as listPersonalities,
  Nn as loadKnowledgeStore,
  Be as normalizeCapturedValue,
  Or as normalizeInput,
  ee as normalizeSemanticContext,
  Ra as registerPersonality,
  Zi as sanitizeObservationSummary,
  In as saveKnowledgeStore,
  zn as seedKnowledgeStore,
  kn as seedTriples,
  vn as selfKnowledgeTriples,
  $t as stripTrailingDeclarativePunctuation,
  Xi as validateObservationSummary
};
