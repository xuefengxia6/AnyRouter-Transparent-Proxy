# 使用官方 Python 3.12 slim 镜像作为基础镜像
FROM python:3.12-slim

# 设置工作目录
WORKDIR /app

# 设置环境变量
# PYTHONUNBUFFERED: 确保 Python 输出直接显示到控制台
# PYTHONDONTWRITEBYTECODE: 防止 Python 生成 .pyc 文件
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

# 复制依赖文件
COPY requirements.txt .

# 安装 Python 依赖
RUN pip install --no-cache-dir -r requirements.txt

# 复制应用代码
COPY anthropic_proxy.py .

# 复制环境变量示例文件（可选）
# COPY .env.example .

# 暴露端口（默认 8088）
EXPOSE 8088

# 健康检查
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import httpx; httpx.get('http://localhost:8088/', timeout=5)"

# 启动应用
CMD ["uvicorn", "anthropic_proxy:app", "--host", "0.0.0.0", "--port", "8088"]