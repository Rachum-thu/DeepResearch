# DeepResearch Bench 完整执行流程分析

## 📋 总体架构

```
run_bench_subset.sh
    └── run_multi_react.py
            └── MultiTurnReactAgent._run()
                    ├── call_server() → OpenRouter API
                    ├── TOOL_MAP[tool_name].call()
                    │   ├── Search (tool_search.py)
                    │   ├── Visit (tool_visit.py)
                    │   └── Scholar (tool_scholar.py)
                    └── Output: iter1.jsonl
```

---

## 🔄 详细执行流程

### 阶段 1：脚本初始化 (run_bench_subset.sh)

**文件**: `script/run_bench_subset.sh`

```bash
1. 加载环境变量
   ├── source /shared/data3/.../CubeScholar/.env.keys
   │   └── OPENROUTER_API_KEY, JINA_API_KEYS, GEMINI_API_KEY 等
   └── source third_party/DeepResearch/.env
       └── SERPER_KEY_ID, API_KEY, SUMMARY_MODEL_NAME 等

2. 配置参数
   ├── DATASET: data/deepresearch_bench_subset/bench_queries.jsonl
   ├── OUTPUT_DIR: output/deepresearch_bench_subset
   ├── MODEL_NAME: alibaba/tongyi-deepresearch-30b-a3b
   ├── MAX_WORKERS: 1
   └── ROLLOUT_COUNT: 1

3. 调用 Python 脚本
   └── python -u inference/run_multi_react.py \
       --dataset <DATASET> \
       --output <OUTPUT_DIR> \
       --model <MODEL_NAME> \
       --max_workers <MAX_WORKERS> \
       --roll_out_count <ROLLOUT_COUNT>
```

**输入数据格式** (`bench_queries.jsonl`):
```json
{"question": "问题内容", "answer": ""}
```

---

### 阶段 2：主控制流程 (run_multi_react.py)

**文件**: `inference/run_multi_react.py`

```python
1. 数据加载与处理
   ├── 读取 JSONL 文件
   ├── 数据分片 (支持分布式处理)
   └── 检查已完成的任务 (支持断点续跑)

2. 输出目录结构
   └── output/deepresearch_bench_subset/
       └── tongyi-deepresearch-30b-a3b_sglang/
           └── bench_queries/
               └── iter1.jsonl  ← 最终输出

3. Agent 初始化 (第169-173行)
   llm_cfg = {
       'model': 'alibaba/tongyi-deepresearch-30b-a3b',
       'generate_cfg': {
           'max_input_tokens': 320000,
           'max_retries': 10,
           'temperature': 0.6,
           'top_p': 0.95,
           'presence_penalty': 1.1
       }
   }

   test_agent = MultiTurnReactAgent(
       llm=llm_cfg,
       function_list=["search", "visit", "google_scholar"]
   )

4. 并行处理 (第177-228行)
   ├── ThreadPoolExecutor(max_workers=1)
   ├── 对每个问题调用: test_agent._run(task, model)
   └── 结果写入: iter1.jsonl
       ├── 成功: {"question", "answer", "messages", "prediction", "termination"}
       └── 失败: {"question", "error", "prediction": "[Failed]"}
```

---

### 阶段 3：ReAct Agent 推理循环 (react_agent.py)

**文件**: `inference/react_agent.py`

#### 3.1 初始化 (_run 方法, 第129-146行)

```python
输入:
  data = {"item": {"question": "...", "answer": ""}, "planning_port": 6001}

初始化:
  messages = [
      {"role": "system", "content": SYSTEM_PROMPT + "Current date: 2025-11-08"},
      {"role": "user", "content": question}
  ]

  MAX_LLM_CALL_PER_RUN = 100  # 最多调用100次
  timeout = 150分钟
```

#### 3.2 主推理循环 (第147-235行)

```python
while num_llm_calls_available > 0:
    round += 1

    # 步骤1: 调用 LLM (OpenRouter API)
    content = self.call_server(messages, planning_port)
    # 返回格式: "<think>...</think>\n<tool_call>{...}</tool_call>"
    #           或 "<think>...</think>\n<answer>...</answer>"

    messages.append({"role": "assistant", "content": content})

    # 步骤2: 解析工具调用
    if '<tool_call>' in content:
        tool_call = JSON.parse(content 中的 tool_call)
        # 示例: {"name": "search", "arguments": {"query": ["..."]}

        # 步骤3: 执行工具
        result = self.custom_call_tool(tool_name, tool_args)

        # 步骤4: 工具结果添加到对话
        messages.append({
            "role": "user",
            "content": "<tool_response>\n" + result + "\n</tool_response>"
        })

    # 步骤5: 检查是否完成
    if '<answer>' in content:
        prediction = extract_answer(content)
        break

    # 步骤6: 检查 token 限制 (110K tokens)
    token_count = self.count_tokens(messages)
    if token_count > 110 * 1024:
        # 强制要求生成最终答案
        messages[-1]['content'] = "You have reached max context..."
        content = self.call_server(messages)
        break
```

**循环终止条件**:
1. ✅ 模型生成 `<answer>` 标签
2. ⏱️ 超过150分钟
3. 🔢 超过100次LLM调用
4. 📏 超过110K tokens

---

### 阶段 4：工具系统 (Tools)

#### 4.1 工具注册 (第31-38行)

```python
TOOL_CLASS = [
    FileParser(),      # 解析PDF/Office文件 (已禁用)
    Scholar(),         # Google学术搜索
    Visit(),          # 网页访问和总结
    Search(),         # 网页搜索
    PythonInterpreter(), # Python代码执行 (已禁用)
]
TOOL_MAP = {tool.name: tool for tool in TOOL_CLASS}
```

#### 4.2 Search 工具 (`tool_search.py`)

```python
输入: {"query": ["查询1", "查询2", ...]}

流程:
1. 使用 Serper API 进行 Google 搜索
   └── GET https://google.serper.dev/search
       Headers: {"X-API-KEY": SERPER_KEY_ID}

2. 返回格式:
   Search results for query "xxx":
   [1] Title: ...
       Link: https://...
       Snippet: ...
   [2] ...
```

**环境变量**: `SERPER_KEY_ID`

#### 4.3 Visit 工具 (`tool_visit.py`)

```python
输入: {"url": ["https://...", ...], "goal": "获取...信息"}

流程:
1. Jina 抓取网页 (jina_readpage, 第132-167行)
   └── GET https://r.jina.ai/{url}
       Headers: {"Authorization": "Bearer {JINA_API_KEYS}"}
   └── 返回: 网页的 markdown 格式文本

2. LLM 总结网页 (call_server, 第99-129行)
   ├── 使用 API_KEY + API_BASE (OpenAI 兼容接口)
   ├── 模型: SUMMARY_MODEL_NAME (默认 gpt-4o-mini)
   └── Prompt: EXTRACTOR_PROMPT
       要求输出 JSON: {"rational", "evidence", "summary"}

3. 重试机制 (第202-221行)
   ├── 如果总结失败，逐步截断网页内容
   │   └── 359684 → 251778 → 176244 → 123370 → 25000 chars
   └── 最多3次重试

4. 返回格式:
   The useful information in {url} for user goal {goal}:

   Evidence in page:
   [提取的关键信息]

   Summary:
   [总结段落]
```

**环境变量**:
- `JINA_API_KEYS` - Jina Reader API
- `API_KEY` - OpenAI API Key
- `API_BASE` - OpenAI API Base URL
- `SUMMARY_MODEL_NAME` - 总结模型名称

#### 4.4 Scholar 工具 (`tool_scholar.py`)

```python
输入: {"query": ["学术查询1", "学术查询2", ...]}

流程:
1. 使用 Serper API 进行 Google Scholar 搜索
   └── GET https://google.serper.dev/scholar
       Headers: {"X-API-KEY": SERPER_KEY_ID}

2. 返回格式:
   Scholar results for query "xxx":
   [1] Title: ...
       Link: https://scholar.google.com/...
       Snippet: ...
       Citations: 123
```

**环境变量**: `SERPER_KEY_ID`

---

### 阶段 5：LLM API 调用 (call_server)

**文件**: `inference/react_agent.py` (第59-110行)

```python
def call_server(self, msgs, planning_port, max_tries=10):
    # 配置
    openai_api_key = os.getenv("OPENROUTER_API_KEY", "")
    openai_api_base = "https://openrouter.ai/api/v1"

    client = OpenAI(
        api_key=openai_api_key,
        base_url=openai_api_base,
        timeout=600.0,
    )

    # 重试机制 (指数退避)
    for attempt in range(max_tries):
        try:
            chat_response = client.chat.completions.create(
                model="alibaba/tongyi-deepresearch-30b-a3b",
                messages=msgs,
                stop=["\n<tool_response>", "<tool_response>"],
                temperature=0.85,  # 从 llm_generate_cfg
                top_p=0.95,
                presence_penalty=1.1,
                max_tokens=10000
            )

            content = chat_response.choices[0].message.content

            # OpenRouter 特定: 提取 reasoning
            reasoning_content = "<think>\n" + chat_response.choices[0].message.reasoning + "\n</think>"
            content = reasoning_content + content

            return content.strip()

        except (APIError, APIConnectionError, APITimeoutError) as e:
            # 指数退避重试
            sleep_time = base_sleep_time * (2 ** attempt) + random(0, 1)
            time.sleep(min(sleep_time, 30))

    return "vllm server error!!!"
```

**响应格式示例**:
```
<think>
用户询问...我需要先搜索...
</think>

<tool_call>
{"name": "search", "arguments": {"query": ["查询关键词"]}}
</tool_call>
```

或最终答案:
```
<think>
根据收集的信息...
</think>

<answer>
[最终研究报告内容]
</answer>
```

---

### 阶段 6：输出格式

**文件**: `output/deepresearch_bench_subset/tongyi-deepresearch-30b-a3b_sglang/bench_queries/iter1.jsonl`

每行一个JSON对象:

```json
{
  "question": "用户的问题",
  "answer": "",  // 参考答案(通常为空)
  "messages": [
    {"role": "system", "content": "..."},
    {"role": "user", "content": "..."},
    {"role": "assistant", "content": "<think>...</think>\n<tool_call>...</tool_call>"},
    {"role": "user", "content": "<tool_response>...</tool_response>"},
    ...
    {"role": "assistant", "content": "<think>...</think>\n<answer>...</answer>"}
  ],
  "prediction": "从 <answer> 标签中提取的最终答案",
  "termination": "answer" | "exceed available llm calls" | "token limit reached" | ...
}
```

**prediction 字段**就是最终生成的研究报告！

---

## 🔑 关键配置总结

### 环境变量 (.env.keys + .env)

```bash
# API Keys
OPENROUTER_API_KEY     # 主推理模型 (alibaba/tongyi-deepresearch-30b-a3b)
JINA_API_KEYS          # 网页抓取 (Jina Reader)
SERPER_KEY_ID          # 搜索引擎 (Google/Scholar)
API_KEY                # 网页总结 (OpenAI compatible)
API_BASE               # OpenAI API Base URL
SUMMARY_MODEL_NAME     # 网页总结模型 (如 gpt-4o-mini)
```

### 超参数

```python
temperature: 0.85          # 模型创造性
top_p: 0.95               # nucleus sampling
presence_penalty: 1.1     # 重复惩罚
max_tokens: 10000         # 单次响应最大token

MAX_LLM_CALL_PER_RUN: 100  # 最多调用次数
max_input_tokens: 320000   # 最大上下文长度
timeout: 150 minutes       # 超时时间
```

### 启用的工具

```python
function_list = ["search", "visit", "google_scholar"]
```

---

## 📊 性能指标

### 单个问题预计消耗

- **LLM 调用次数**: 10-50 次
- **时间**: 5-30 分钟
- **Tokens**:
  - 输入: 累计 50K-200K tokens
  - 输出: 累计 10K-50K tokens
- **API 调用**:
  - OpenRouter: 10-50 次
  - Serper: 5-20 次
  - Jina: 10-30 次
  - OpenAI (总结): 10-30 次

### 3个问题 (subset)

- **总时间**: 15-90 分钟
- **并发数**: 1 worker (串行处理)

### 100个问题 (full)

- **总时间**: 5-10 小时
- **并发数**: 3 workers (并行处理)

---

## 🔧 关键代码位置

| 功能 | 文件 | 行号 |
|-----|------|------|
| 启动脚本 | `script/run_bench_subset.sh` | 全部 |
| 主控制流程 | `inference/run_multi_react.py` | 13-232 |
| Agent初始化 | `inference/run_multi_react.py` | 169-173 |
| ReAct循环 | `inference/react_agent.py` | 147-235 |
| LLM调用 | `inference/react_agent.py` | 59-110 |
| 工具调用 | `inference/react_agent.py` | 237-256 |
| Search工具 | `inference/tool_search.py` | 全部 |
| Visit工具 | `inference/tool_visit.py` | 全部 |
| Scholar工具 | `inference/tool_scholar.py` | 全部 |
| System Prompt | `inference/prompt.py` | 1-35 |

---

## 🐛 调试技巧

### 1. 查看实时日志
```bash
tail -f output/deepresearch_bench_subset/.../iter1.jsonl
```

### 2. 检查中间结果
每次LLM调用都会打印:
```
Round 1: <think>...</think>\n<tool_call>...</tool_call>
```

### 3. 检查Token使用
```
round: 15, token count: 19947
```

### 4. 工具调用日志
```
[visit] Summary url[https://...] attempt 1/3, content length: 359684
```

---

## 📝 待优化点

1. **并发能力**: 当前 max_workers=1，可以提升到 3-5
2. **缓存机制**: 重复的搜索和网页访问没有缓存
3. **错误恢复**: 工具失败时缺乏优雅降级
4. **成本优化**: 网页总结可以使用更便宜的模型
5. **输出格式**: prediction 字段可能包含 `<think>` 等标签，需要清理

---

生成时间: 2025-11-08
