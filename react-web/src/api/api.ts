import axios, { AxiosRequestConfig } from "axios";
import { onRequest, onRequestError } from "./onRequest";

export const BASE_URL = "";

export const fetchData = axios.create({
  baseURL: BASE_URL,
  headers: {
    "Content-type": "application/json",
    Accept: "application/json",
  },
});

export const postData = axios.create({
  baseURL: BASE_URL,
  headers: {
    "Content-type": "text/plain;charset=utf-8",
    Accept: "text/plain;charset=utf-8",
  },
});

fetchData.interceptors.request.use(
  (config: AxiosRequestConfig) => onRequest(config),
  onRequestError
);

postData.interceptors.request.use(
  (config: AxiosRequestConfig) => onRequest(config),
  onRequestError
);
