import dayjs from "dayjs";
import utc from "dayjs/plugin/utc";

dayjs.extend(utc);

type DayJSInput = string | number | dayjs.Dayjs | Date;

export const formatDate = (
  date: DayJSInput,
  format: string = "MMM D, YYYY h:mm A Z"
) => dayjs(date).format(format);
